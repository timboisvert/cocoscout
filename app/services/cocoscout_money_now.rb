# frozen_string_literal: true

# CocoScout's own money at this moment, for the top of superadmin Finances:
# how much of its profit is still in Stripe, how much of that it can take
# out today, and what organizations owe it. Not tied to a period.
#
#   profit to date      every dollar earned less every dollar spent
#   sent to our bank    payouts to CocoScout's bank, less money added back
#   paid by hand        organizations CocoScout paid from its own bank: the
#                       money their balances gave up stays in Stripe, ours
#   adjustments         the opening difference and lines explained by hand
#   = ours in Stripe    the sum of CocoScout's ledger
#
# Of ours in Stripe, what can go to the bank today is capped by Stripe's
# available balance (the rest of Stripe's balance is still arriving), from
# the latest daily check.
class CocoScoutMoneyNow
  # An unpaid bill this many days old, or one whose payment failed, is late.
  LATE_AFTER = 7.days

  Bill = Data.define(:invoice, :state, :days_old)

  def initialize(check: PlatformReconciliation.latest, now: Time.current)
    @check = check
    @now = now
  end

  attr_reader :check

  def sums
    @sums ||= CocoScoutLedgerEntry.group(:entry_type).sum(:amount_cents)
  end

  def profit_cents
    (CocoScoutLedgerEntry.types_in(:income) + CocoScoutLedgerEntry.types_in(:cost)).sum { |type| sums[type].to_i }
  end

  def sent_to_bank_cents
    -(sums["payout_to_bank"].to_i + sums["added_from_bank"].to_i)
  end

  def paid_by_hand_cents
    sums["paid_by_hand"].to_i
  end

  def adjustments_cents
    CocoScoutLedgerEntry.types_in(:adjustment).sum { |type| sums[type].to_i }
  end

  def ours_in_stripe_cents
    profit_cents - sent_to_bank_cents + paid_by_hand_cents + adjustments_cents
  end

  # Stripe's available balance at the last check; nil when it couldn't be asked.
  def stripe_available_cents
    check&.details&.dig("stripe_available_cents")
  end

  # What CocoScout can send to its bank today.
  def withdrawable_cents
    ours = ours_in_stripe_cents
    return 0 unless ours.positive?
    return 0 if stripe_available_cents.nil?

    [ [ ours, stripe_available_cents ].min, 0 ].max
  end

  # Ours, but still on its way into Stripe's available balance.
  def arriving_cents
    [ ours_in_stripe_cents - withdrawable_cents, 0 ].max
  end

  # Every bill not yet paid, oldest first, with where it stands:
  #   :late        payment failed, or unpaid more than LATE_AFTER
  #   :collecting  a bank debit on its way
  #   :due         billed, waiting on its automatic charge
  def unpaid_bills
    @unpaid_bills ||= BillingInvoice.where(status: %w[draft open uncollectible]).includes(:organization)
                                    .order(Arel.sql("COALESCE(finalized_at, created_at)")).map do |invoice|
      billed = invoice.finalized_at || invoice.created_at
      days = ((@now - billed) / 1.day).floor
      state = if invoice.failed? || (billed < @now - LATE_AFTER && !invoice.collecting?) then :late
      elsif invoice.collecting? then :collecting
      else :due
      end
      Bill.new(invoice: invoice, state: state, days_old: days)
    end
  end

  def unpaid_cents(state = nil)
    bills = state ? unpaid_bills.select { |bill| bill.state == state } : unpaid_bills
    bills.sum { |bill| owed(bill.invoice) }
  end

  def owed(invoice)
    invoice.status == "draft" ? invoice.amount_due_cents : invoice.amount_remaining_cents
  end

  # Usage building up this month that no bill carries yet: each billed
  # organization's performers and staff so far, at their prices.
  def usage_so_far
    @usage_so_far ||= begin
      month = @now.to_date.beginning_of_month
      performers = PerformerActivation.for_month(month).group(:organization_id).count
      staff = StaffActivation.for_month(month).group(:organization_id).count
      orgs = Organization.where(id: (performers.keys + staff.keys).uniq).select(&:bills_usage?)
      rows = orgs.map do |org|
        cents = performers[org.id].to_i * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS +
                staff[org.id].to_i * StaffBillingService::PER_ACTIVE_STAFF_CENTS
        { organization: org, performers: performers[org.id].to_i, staff: staff[org.id].to_i, cents: cents }
      end
      rows.select { |row| row[:cents].positive? }.sort_by { |row| -row[:cents] }
    end
  end

  def usage_so_far_cents
    usage_so_far.sum { |row| row[:cents] }
  end

  # Every bill in a period, newest first: did each organization pay?
  def self.bills_in(range)
    scope = BillingInvoice.where.not(status: "void").includes(:organization)
    scope = scope.where("COALESCE(finalized_at, created_at) BETWEEN ? AND ?", range.first, range.last) if range
    scope.order(Arel.sql("COALESCE(finalized_at, created_at) DESC"))
  end
end

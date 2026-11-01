# frozen_string_literal: true

# CocoScout's own money at this moment, for the top of superadmin Finances:
# how much of its profit is still in Stripe, how much of that it can take
# out today, and what organizations owe it. Not tied to a period.
#
#   earned to date      every dollar earned (bills sent count, paid or not)
#                       less every dollar spent
#   not yet collected   bills sent and not yet paid
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

  # Earned less spent since we started, counting every bill sent, and not
  # a second bill for a month that was paid (that's owed back).
  def profit_cents
    collected_profit_cents + not_collected_cents - owed_back_cents
  end

  # The same, counting only what's been paid: the ledger.
  def collected_profit_cents
    (CocoScoutLedgerEntry.types_in(:income) + CocoScoutLedgerEntry.types_in(:cost)).sum { |type| sums[type].to_i }
  end

  def not_collected_cents
    @not_collected_cents ||= BillingInvoice.earned_unpaid.sum(:amount_remaining_cents)
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
    collected_profit_cents - sent_to_bank_cents + paid_by_hand_cents + adjustments_cents
  end

  # Moves between Stripe and CocoScout's bank, newest first: payouts to the
  # bank and money added back, or (by_hand) organizations paid from it.
  def bank_moves(by_hand: false)
    types = by_hand ? %w[paid_by_hand] : %w[payout_to_bank added_from_bank]
    CocoScoutLedgerEntry.where(entry_type: types).includes(:organization).order(occurred_at: :desc)
  end

  # Stripe's available balance at the last check; nil when it couldn't be asked.
  def stripe_available_cents
    check&.details&.dig("stripe_available_cents")
  end

  # What CocoScout can send to its bank today: ours, less what we owe back.
  def withdrawable_cents
    ours = ours_in_stripe_cents - owed_back_cents
    return 0 unless ours.positive?
    return 0 if stripe_available_cents.nil?

    [ [ ours, stripe_available_cents ].min, 0 ].max
  end

  # Ours, but still on its way into Stripe's available balance.
  def arriving_cents
    [ ours_in_stripe_cents - owed_back_cents - withdrawable_cents, 0 ].max
  end

  # Every bill not yet paid, oldest first, with where it stands:
  #   :duplicate   bills a month another bill already carries: void it
  #   :late        payment failed, or unpaid more than LATE_AFTER
  #   :collecting  a bank debit on its way
  #   :due         billed, waiting on its automatic charge
  def unpaid_bills
    @unpaid_bills ||= begin
      duplicates = BillingInvoice.duplicate_ids
      BillingInvoice.where(status: %w[draft open uncollectible]).includes(:organization)
                    .order(Arel.sql("COALESCE(finalized_at, created_at)")).map do |invoice|
        billed = invoice.finalized_at || invoice.created_at
        days = ((@now - billed) / 1.day).floor
        state = if duplicates.include?(invoice.id) then :duplicate
        elsif invoice.failed? || (billed < @now - LATE_AFTER && !invoice.collecting?) then :late
        elsif invoice.collecting? then :collecting
        else :due
        end
        Bill.new(invoice: invoice, state: state, days_old: days)
      end
    end
  end

  # Second bills for a month that were paid before anyone caught them, not
  # yet given back: usage:overbilled[ORG_ID,refund] refunds them.
  def paid_twice
    @paid_twice ||= begin
      refunded = StripeBalanceTransaction.where(category: "billing_refund", matched_type: "BillingInvoice").group(:matched_id).sum(:amount_cents)
      BillingInvoice.where(id: BillingInvoice.duplicate_ids, status: "paid").includes(:organization).order(:id)
                    .select { |bill| bill.amount_paid_cents + refunded[bill.id].to_i > 0 }
    end
  end

  def owed_back_cents
    @owed_back_cents ||= begin
      refunded = StripeBalanceTransaction.where(category: "billing_refund", matched_type: "BillingInvoice", matched_id: paid_twice.map(&:id))
                                         .group(:matched_id).sum(:amount_cents)
      paid_twice.sum { |bill| bill.amount_paid_cents + refunded[bill.id].to_i }
    end
  end

  def unpaid_cents(state = nil)
    bills = state ? unpaid_bills.select { |bill| bill.state == state } : unpaid_bills.reject { |bill| bill.state == :duplicate }
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

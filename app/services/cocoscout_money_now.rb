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

  def initialize(check: PlatformReconciliation.latest, now: Time.current, give_back: nil)
    @check = check
    @now = now
    @give_back = give_back
  end

  attr_reader :check

  def sums
    @sums ||= CocoScoutLedgerEntry.group(:entry_type).sum(:amount_cents)
  end

  # Earned less spent since we started: counting every bill sent, less what
  # we charged too much (owed back), less credit given back that hasn't paid
  # a bill yet.
  def profit_cents
    collected_profit_cents + not_collected_cents - owed_back_cents - unused_credit_cents
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
    ours = ours_in_stripe_cents - held_back_cents
    return 0 unless ours.positive?
    return 0 if stripe_available_cents.nil?

    [ [ ours, stripe_available_cents ].min, 0 ].max
  end

  # Ours, but still on its way into Stripe's available balance.
  def arriving_cents
    [ ours_in_stripe_cents - held_back_cents - withdrawable_cents, 0 ].max
  end

  # -- Short: Stripe holds less than the organizations' balances add up to.

  # How much less. Zero when it holds enough.
  def short_cents
    [ -ours_in_stripe_cents, 0 ].max
  end

  # Bills we're owed that are coming (on their way, or charging
  # automatically), soonest first, with the day each should land.
  Coming = Data.define(:invoice, :cents, :lands_on)

  def coming_in
    @coming_in ||= unpaid_bills.select { |bill| %i[collecting due].include?(bill.state) }.map do |bill|
      invoice = bill.invoice
      on = invoice.lands_on || invoice.next_payment_attempt_at&.to_date&.then { |day| business_days_after(day, BillingInvoice::BANK_DEBIT_BUSINESS_DAYS) } ||
           invoice.due_at&.to_date
      Coming.new(invoice: invoice, cents: owed(invoice), lands_on: on)
    end.sort_by { |row| row.lands_on || Date.new(9999) }
  end

  def coming_in_cents
    coming_in.sum(&:cents)
  end

  # Still short once everything coming in has landed.
  def short_after_coming_cents
    [ short_cents - coming_in_cents, 0 ].max
  end

  # The day the last of it lands, when they all say.
  def coming_in_by
    days = coming_in.map(&:lands_on)
    days.all? ? days.max : nil
  end

  # What a ticket has left CocoScout lately, after Stripe's processing: the
  # last 90 days of ticket fees, processing buyers paid, refunds, and
  # Stripe's processing on tickets, over the tickets sold. Nil without sales.
  def per_ticket_cents
    @per_ticket_cents ||= begin
      recent = CocoScoutLedgerEntry.where(occurred_at: (@now - 90.days)..@now)
      income = recent.where(entry_type: %w[ticket_fee ticket_processing ticket_refund]).sum(:amount_cents)
      cost = recent.where(entry_type: "processing_cost", source_type: %w[TicketOrder TicketPassHolding]).sum(:amount_cents)
      tickets = recent.where(entry_type: "ticket_fee").sum(:amount_cents) / TicketPricing::PLATFORM_FEE_CENTS
      net = income + cost
      tickets.positive? && net.positive? ? net / tickets.to_f : nil
    end
  end

  # About how many more tickets close what's left.
  def tickets_to_close(cents = short_after_coming_cents)
    return nil unless per_ticket_cents && cents.positive?

    (cents / per_ticket_cents).ceil
  end

  # This month's usage, billed on the 1st and taken from the banks on file:
  # about when it lands.
  def usage_lands_on
    business_days_after(@now.to_date.next_month.beginning_of_month, BillingInvoice::BANK_DEBIT_BUSINESS_DAYS)
  end

  # What to add from CocoScout's bank to be even today, or once what's
  # coming has landed: whole dollars.
  def suggested_add_cents(after_coming: true)
    cents = after_coming ? short_after_coming_cents : short_cents
    (cents / 100.0).ceil * 100
  end

  # An organization's next bill from us, so a credit has somewhere to go:
  # its usage on the 1st (and what's built up so far), or its Pro renewal.
  # Nil when nothing is coming, and a credit would only sit there.
  def next_bill_for(organization)
    if organization.bills_usage?
      so_far = usage_so_far.find { |row| row[:organization].id == organization.id }&.dig(:cents).to_i
      { on: @now.to_date.next_month.beginning_of_month, what: "usage", so_far_cents: so_far }
    elsif !organization.comped? && organization.subscription_status.in?(SubscriptionSyncService::ACCESS_STATUSES) && organization.subscription_current_period_end
      { on: organization.subscription_current_period_end.to_date, what: "Pro plan", so_far_cents: nil }
    end
  end

  # Money CocoScout added from its bank that Stripe hasn't made available yet.
  def adding_from_bank
    StripeBalanceTransaction.where(category: "added_from_bank", status: "pending").order(:occurred_at)
  end

  # Every bill not yet paid, oldest first, with where it stands:
  #   :duplicate   bills a month another bill already carries: void it
  #   :late        payment failed, or unpaid more than LATE_AFTER with
  #                nothing on its way and no charge or due date ahead
  #   :collecting  the money is on its way (a bank debit takes days)
  #   :due         billed, waiting on its automatic charge or its due date
  def unpaid_bills
    @unpaid_bills ||= begin
      duplicates = BillingInvoice.duplicate_ids
      BillingInvoice.where(status: %w[draft open uncollectible]).includes(:organization)
                    .order(Arel.sql("COALESCE(finalized_at, created_at)")).map do |invoice|
        billed = invoice.finalized_at || invoice.created_at
        days = ((@now - billed) / 1.day).floor
        state = if duplicates.include?(invoice.id) then :duplicate
        elsif invoice.late?(now: @now, after: LATE_AFTER) then :late
        elsif invoice.collecting? then :collecting
        else :due
        end
        Bill.new(invoice: invoice, state: state, days_old: days)
      end
    end
  end

  # Every overcharge not yet given back (UsageOverbilling): a second bill
  # for a month, or a bill charged more than its month's paid work.
  def give_back
    @give_back ||= UsageOverbilling.all_rows
  end

  # What we charged too much and haven't given back. A second bill not yet
  # paid isn't counted anywhere, so it isn't owed back either.
  def owed_back_cents
    give_back.sum { |row| row.invoice.status == "paid" || !row.duplicate ? row.over_cents : 0 }
  end

  # Of that, money already in Stripe: paid overcharges.
  def owed_back_paid_cents
    give_back.select(&:refundable_now?).sum(&:over_cents)
  end

  # Credit given back on bills that no bill has used up yet: what we'll
  # bill less for.
  def unused_credit_cents
    @unused_credit_cents ||= BillingInvoice.unused_credit_cents
  end

  # In Stripe and ours, but spoken for: overcharges to refund and credit
  # that pays down coming bills.
  def held_back_cents
    owed_back_paid_cents + unused_credit_cents
  end

  def unpaid_cents(state = nil)
    bills = state ? unpaid_bills.select { |bill| bill.state == state } : unpaid_bills.reject { |bill| bill.state == :duplicate }
    bills.sum { |bill| owed(bill.invoice) }
  end

  def owed(invoice)
    invoice.status == "draft" ? invoice.amount_due_cents : invoice.amount_remaining_cents
  end

  # Usage building up this month that no bill carries yet: each billed
  # organization's people paid so far at their prices, and its bank debits
  # beyond the free ones.
  def usage_so_far
    @usage_so_far ||= begin
      month = @now.to_date.beginning_of_month
      performers = PerformerActivation.for_month(month).group(:organization_id).count
      staff = StaffActivation.for_month(month).group(:organization_id).count
      range = UsageRules.range_for(month)
      debiting = PayoutBatch.where.not(funding_payment_intent_id: nil).where("COALESCE(funding_started_at, created_at) BETWEEN ? AND ?", range.first, range.last)
                            .distinct.pluck(:organization_id) +
                 BalanceTopUp.where(created_at: range).where.not(stripe_payment_intent_id: nil).distinct.pluck(:organization_id) +
                 BalanceWithdrawal.not_failed.where(created_at: range).distinct.pluck(:organization_id)
      orgs = Organization.where(id: (performers.keys + staff.keys + debiting).uniq).select(&:bills_usage?)
      rows = orgs.map do |org|
        debits = UsageRules.extra_bank_debits(org, month)
        cents = performers[org.id].to_i * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS +
                staff[org.id].to_i * StaffBillingService::PER_ACTIVE_STAFF_CENTS + debits * UsageRules::EXTRA_BANK_DEBIT_CENTS +
                UsageRules.withdrawal_fee_cents(org, month)
        { organization: org, performers: performers[org.id].to_i, staff: staff[org.id].to_i, extra_debits: debits, cents: cents }
      end
      rows.select { |row| row[:cents].positive? }.sort_by { |row| -row[:cents] }
    end
  end

  def usage_so_far_cents
    usage_so_far.sum { |row| row[:cents] }
  end

  def business_days_after(day, count)
    count.times { day = day.next_day; day = day.next_day while day.saturday? || day.sunday? }
    day
  end

  # Every bill in a period, newest first: did each organization pay?
  def self.bills_in(range)
    scope = BillingInvoice.where.not(status: "void").includes(:organization)
    scope = scope.where("COALESCE(finalized_at, created_at) BETWEEN ? AND ?", range.first, range.last) if range
    scope.order(Arel.sql("COALESCE(finalized_at, created_at) DESC"))
  end
end

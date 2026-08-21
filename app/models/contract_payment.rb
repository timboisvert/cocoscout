# frozen_string_literal: true

class ContractPayment < ApplicationRecord
  belongs_to :contract
  belongs_to :show, optional: true

  # This payment's slot in a payout run, if it's been added to one. dependent:
  # :destroy so removing it detaches from the run (see PayoutContribution).
  has_one :payout_contribution, as: :source, dependent: :destroy

  # Direction: whether they pay us or we pay them
  enum :direction, {
    incoming: "incoming",  # They pay us (rental fee, deposit)
    outgoing: "outgoing"   # We pay them (services, reimbursements)
  }, prefix: :direction

  # Payment status
  enum :status, {
    pending: "pending",
    paid: "paid",
    overdue: "overdue",
    cancelled: "cancelled"
  }, default: :pending, prefix: :status

  # How an incoming payment is settled: they pay it directly (pay link /
  # recorded payment), or it's taken out of their payout when their revenue
  # share joins a payout run (see ContractorPayoutRunService).
  SETTLEMENT_METHODS = %w[direct payout_deduction].freeze

  # Ways money owed TO us can arrive outside CocoScout's Stripe rail, as a
  # manager records them — [label, value], in the order offered. Recording is
  # a statement of fact and is never gated by what the contract told the payer
  # they may use (Contract::OFFLINE_PAYMENT_METHODS is that policy). Venmo and
  # Zelle stay here for hand-recording even though nothing settles through them.
  RECEIVED_PAYMENT_METHODS = [
    [ "Cash", "cash" ],
    [ "Check", "check" ],
    [ "Zelle", "zelle" ],
    [ "Venmo", "venmo" ],
    [ "Bank transfer", "bank_transfer" ],
    [ "Other", "other" ]
  ].freeze

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, unless: :amount_tbd?
  validates :due_date, presence: true
  validates :direction, presence: true
  validates :settlement_method, inclusion: { in: SETTLEMENT_METHODS }

  scope :upcoming, -> { status_pending.where("due_date >= ?", Date.current).order(:due_date) }
  scope :overdue, -> { status_pending.where("due_date < ?", Date.current).order(:due_date) }
  scope :by_due_date, -> { order(:due_date) }

  # --- Folded service charges ---------------------------------------------------
  # A per-event service they pay us for (a booth tech on the night) is billed
  # INSIDE that event's payment, not beside it: "$350 rent + $50 booth tech" is
  # one $400 payment with one pay link. `components` remembers what was folded
  # in — [{ "kind" => "service", "name" => "Booth Tech", "amount" => 50.0,
  # "billed_for" => "2026-10-10" }] — so the row can say "incl. Booth Tech $50"
  # and an amendment can unfold and re-bill exactly what it added.

  def service_components
    Array(components).select { |c| c["kind"] == "service" }
  end

  def components_total
    service_components.sum { |c| c["amount"].to_f }.round(2)
  end

  # The payment's own amount before the services folded into it.
  def base_amount
    (amount.to_f - components_total).round(2)
  end

  def includes_services?
    service_components.any?
  end

  # "incl. Booth Tech $50.00" / "incl. Booth Tech $50.00 and Sound $25.00"
  def folded_services_summary
    return nil unless includes_services?

    parts = service_components.map { |c| "#{c['name']} #{ActiveSupport::NumberHelper.number_to_currency(c['amount'].to_f)}" }
    "incl. #{parts.to_sentence}"
  end

  # Fold a service charge into this payment: the amount grows, the component is
  # remembered. Only for a pending payment nobody has collected or committed.
  def fold_service!(name:, amount:, billed_for: nil)
    raise ArgumentError, "can't fold into a settled payment" unless status_pending? && !in_payout_run?

    update!(amount: (self.amount.to_f + amount.to_f).round(2),
            components: Array(components) + [ { "kind" => "service", "name" => name, "amount" => amount.to_f.round(2), "billed_for" => billed_for&.to_s }.compact ])
  end

  # Take service charges back out (an amendment re-billing them). Returns the
  # amount removed.
  def unfold_services!(names)
    names = Array(names).map(&:to_s)
    keep, drop = Array(components).partition { |c| c["kind"] != "service" || !names.include?(c["name"].to_s) }
    removed = drop.sum { |c| c["amount"].to_f }.round(2)
    return 0.0 if drop.empty?

    update!(amount: (amount.to_f - removed).round(2), components: keep)
    removed
  end

  # Check if this payment amount is to be determined (e.g., revenue share)
  def amount_tbd?
    amount_tbd
  end

  # Check if this is a revenue share payment (amount determined after events)
  def revenue_share?
    description&.downcase&.include?("revenue share")
  end

  # Check if payment is overdue
  def overdue?
    status_pending? && due_date < Date.current && !nothing_to_hand_back?
  end

  # A settlement that resolved to exactly nothing: on a ticket-revenue deal, the
  # night covered our fee to the penny, so there is nothing to hand back and
  # nothing to collect. Not late, not "set an amount" — done.
  def nothing_to_hand_back?
    status_pending? && direction_outgoing? && !amount_tbd? && amount.to_f.zero? &&
      (contract.ticket_revenue_minus_fee? || contract.revenue_share?)
  end

  # Whether this payment has been added to a payout run.
  def in_payout_run?
    payout_contribution.present?
  end

  # A settlement whose amount is still waiting on ticket sales.
  def awaiting_amount?
    amount_tbd? && amount.to_f.zero?
  end

  # On a minus-fee settlement, the fee we keep out of the night's ticket money.
  # It's ours however the night sells — one that sells under it turns into a
  # shortfall they owe us — so no screen has to say a flat "TBD" about this
  # part. Only the remainder handed back waits on sales. Nil when there's no
  # fee to name, and never on an incoming row (a shortfall carries a real
  # amount, and the fee isn't what it's collecting).
  def guaranteed_fee
    return nil unless awaiting_amount? && direction_outgoing?

    contract.fee_held_back_for(self)
  end

  # Where a payment sits in the payout machinery: nil when it isn't in a run at
  # all (or its run failed/was canceled, which hands it back to us), :in_draft
  # when it's staged in a run nobody has submitted yet, :in_flight once the run
  # is funded and the money is moving. A payment past its due date but sitting
  # in a submitted run isn't late in any way anyone can act on — it's on its
  # way, and saying "overdue" about it is just wrong.
  def payout_stage
    batch = payout_contribution&.payout_batch
    return nil unless batch

    stage = MoneyTodoService.payout_bucket(batch, paid: status_paid?)
    stage if %i[in_draft in_flight].include?(stage)
  end

  # Money they owe us that we've agreed to net out of their payout instead of
  # invoicing. Only meaningful on incoming payments.
  #
  # It also takes a payout to deduct from. A contract with no outgoing money —
  # a rental where they only ever pay us — can never net this out (the netting
  # runs off an outgoing payment joining a run, see ContractorPayoutRunService),
  # so the charge would sit forever with no pay link and no way to record it.
  # Treat it as an ordinary invoice instead.
  def deduct_from_payout?
    return false unless direction_incoming? && settlement_method == "payout_deduction"

    contract.outgoing_settlement?
  end

  # Settled by being netted out of the counterparty's payout run. Display-only
  # for traceability — the run's contributions and ledger entries carry the
  # actual money movement.
  def mark_paid_via_deduction!(reference: nil)
    update!(status: :paid, paid_date: Date.current, payment_method: "payout_deduction", reference_number: reference)
  end

  # --- Paying us online -------------------------------------------------------

  # Whether this payment can be collected through a pay link: money owed TO us,
  # still outstanding, and with a settled amount to charge.
  def collectable_online?
    direction_incoming? && status_pending? && !amount_tbd? && amount.to_f.positive? &&
      !deduct_from_payout?
  end

  # The secret in the shareable /pay/contract/:token link. Minted on first use
  # and then stable, so a link the org already sent keeps working.
  def payment_token!
    return payment_token if payment_token.present?

    # Retry rather than trust a single draw — the column is uniquely indexed.
    begin
      update!(payment_token: SecureRandom.urlsafe_base64(24))
    rescue ActiveRecord::RecordNotUnique
      retry
    end
    payment_token
  end

  def amount_cents
    (amount.to_f * 100).round
  end

  # Records an online payment. Idempotent on the checkout session, so a webhook
  # arriving twice (or racing the success page) settles this once.
  def mark_paid_online!(checkout_session_id:, payment_intent_id: nil)
    return false if status_paid?

    update!(
      status: :paid,
      paid_date: Date.current,
      payment_method: "online",
      reference_number: payment_intent_id,
      stripe_checkout_session_id: checkout_session_id,
      stripe_payment_intent_id: payment_intent_id
    )
    true
  end

  # What CocoScout owes the organization for this payment: what the contractor
  # paid, less what Stripe took to process it. CocoScout keeps no margin here.
  def remittable_cents
    [ amount_cents - stripe_fee_cents.to_i, 0 ].max
  end

  # Marks this payment paid when its payout run pays out (called from
  # PayoutBatchService.settle_item_sources!). Display-only for traceability —
  # the PayoutBatchItem posts the single debiting ledger entry, so this must not
  # touch the ledger.
  def mark_paid_via_payout_run!(reference_id: nil)
    # A deduction line's source is an INCOMING payment already settled by the
    # netting (or carrying a live remainder) — the run paying out must never
    # relabel it as a Stripe payment or resurrect a paid one.
    return if direction_incoming? || status_paid?

    update!(status: :paid, paid_date: Date.current, payment_method: "stripe", reference_number: reference_id)
  end

  # The run that paid this came back — the payee's bank rejected the deposit.
  # Only undoes what a payout run itself did; money recorded by hand or settled
  # by deduction is left alone.
  def mark_unpaid_via_payout_run!
    return unless status_paid? && payment_method == "stripe"

    update!(status: :pending, paid_date: nil, payment_method: nil, reference_number: nil)
  end

  # --- Paying them outside CocoScout -----------------------------------------
  # The payout run is the normal way money we owe reaches a contractor, but it
  # can only reach someone who's connected a bank. When they haven't, the money
  # still has to get to them somehow — Zelle, a check, cash — and that has to be
  # recordable here or the payment stays "due" forever.

  # Ways a manager may say they paid someone by hand. Mirrors the show payout
  # rail's manual methods; the org still has to turn each one on in Money
  # settings (Organization#offline_payout_method_choices) before it's offered.
  OFFLINE_PAYOUT_METHODS = %w[cash check zelle venmo other].freeze

  # Money we handed them outside CocoScout. Nothing posts to the ledger: an
  # outgoing contract payment only accrues a balance when it joins a run (that's
  # where ContractorPayoutRunService posts the `earning` entry), so one settled
  # by hand has nothing to offset. Services this contract meant to net out of
  # the payment settle here too — they were waiting on a payout run that is now
  # never coming, and leaving them pending would quietly cost the org the fee.
  def pay_offline!(method:, paid_on: Date.current, reference: nil, deductions: [])
    transaction do
      deductions.each do |charge|
        charge.mark_paid_via_deduction!(
          reference: "Netted out of #{description.presence || 'settlement'} paid #{paid_on.strftime('%b %-d, %Y')}"
        )
      end
      update!(status: :paid, paid_date: paid_on, payment_method: method, reference_number: reference)
    end
  end

  # How a settled incoming payment arrived, for history rows: the offline
  # method when it was recorded by hand, otherwise the rail it moved on.
  def received_via_label
    return nil unless status_paid?

    offline_payment_method_label ||
      case payment_method
      when "online" then "Paid online"
      when "payout_deduction" then "Deducted from payout"
      end
  end

  # Paid by hand rather than through a payout run or a pay link.
  def paid_offline?
    status_paid? && payment_method.in?(OFFLINE_PAYOUT_METHODS)
  end

  # How the money moved, for the paid badge. Nil for methods that speak for
  # themselves (a payout run, a pay link).
  def offline_payment_method_label
    return nil unless paid_offline?

    payment_method == "other" ? "Another way" : payment_method.titleize
  end

  # Mark as paid
  def mark_paid!(paid_on: Date.current, method: nil, reference: nil, amount: nil)
    attrs = {
      status: :paid,
      paid_date: paid_on,
      payment_method: method,
      reference_number: reference
    }
    if amount.present?
      attrs[:amount] = amount.to_f
      attrs[:amount_tbd] = false
    end
    update!(attrs)
  end

  # Display helpers
  def formatted_amount
    prefix = direction_incoming? ? "+" : "-"
    "#{prefix}$#{'%.2f' % amount}"
  end

  # Compute a suggested amount based on contract terms and show financials.
  # Returns { amount: Float, explanation: String, shows: [...] } or nil.
  def suggested_amount_from_financials
    return nil unless amount_tbd? && contract

    linked_shows = contract.shows_for_payment(self)
    shows_with_data = linked_shows.select { |s| s.show_financials&.has_data? }
    return nil if shows_with_data.empty?

    total_revenue = shows_with_data.sum { |s| s.show_financials.total_revenue }
    config = contract.draft_payment_config
    structure = contract.draft_payment_structure

    suggested = case structure
    when "revenue_share"
      pct = direction_incoming? ? config["revenue_our_share"].to_f : config["revenue_their_share"].to_f
      calculated = (total_revenue * pct / 100.0).round(2)
      { amount: calculated, explanation: "#{pct.round(0)}% of revenue" }
    when "per_event"
      per_event_amt = config["per_event_amount"].to_f
      if per_event_amt > 0
        { amount: per_event_amt * linked_shows.size, explanation: "$#{'%.2f' % per_event_amt} per event" }
      end
    when "flat_fee"
      flat_amt = config["flat_fee_amount"].to_f
      fee_direction = config["flat_fee_direction"]
      if fee_direction == "ticket_revenue_minus_fee" && flat_amt > 0
        # Only the fee for the shows this payment settles, so a weekly
        # settlement deducts that week's shows rather than the whole run's.
        fee = contract.flat_fee_for_shows(shows_with_data.size)
        contractor_amount = [ (total_revenue - fee).round(2), 0 ].max
        { amount: contractor_amount, explanation: "Ticket revenue minus $#{'%.2f' % fee} fee" }
      elsif flat_amt > 0
        { amount: flat_amt, explanation: "Flat fee" }
      end
    end

    if suggested
      suggested[:shows] = shows_with_data
      suggested[:total_revenue] = total_revenue
    end

    suggested
  end

  def status_badge_class
    case status
    when "paid" then "badge-success"
    when "pending" then overdue? ? "badge-danger" : "badge-warning"
    when "overdue" then "badge-danger"
    when "cancelled" then "badge-secondary"
    else "badge-secondary"
    end
  end
end

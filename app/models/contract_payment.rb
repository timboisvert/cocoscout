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

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, unless: :amount_tbd?
  validates :due_date, presence: true
  validates :direction, presence: true
  validates :settlement_method, inclusion: { in: SETTLEMENT_METHODS }

  scope :upcoming, -> { status_pending.where("due_date >= ?", Date.current).order(:due_date) }
  scope :overdue, -> { status_pending.where("due_date < ?", Date.current).order(:due_date) }
  scope :by_due_date, -> { order(:due_date) }

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
    status_pending? && due_date < Date.current
  end

  # Whether this payment has been added to a payout run.
  def in_payout_run?
    payout_contribution.present?
  end

  # Money they owe us that we've agreed to net out of their payout instead of
  # invoicing. Only meaningful on incoming payments.
  def deduct_from_payout?
    direction_incoming? && settlement_method == "payout_deduction"
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

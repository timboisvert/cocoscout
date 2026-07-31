# frozen_string_literal: true

class ShowPayoutLineItem < ApplicationRecord
  belongs_to :show_payout
  belongs_to :payee, polymorphic: true, optional: true  # Person or Group (optional for guests)
  belongs_to :manually_paid_by, class_name: "User", optional: true

  has_one :show, through: :show_payout
  has_one :production, through: :show_payout

  has_many :advance_recoveries, dependent: :destroy
  has_many :person_advances, through: :advance_recoveries

  # Ledger entries this line item sourced (its earning, and a payout when paid).
  # dependent: :destroy so a recalculation (line_items.destroy_all) can't orphan
  # ledger entries and inflate a balance.
  has_many :payout_ledger_entries, as: :source, dependent: :destroy

  # This line's slot in a payout run, if it's been added to one. dependent:
  # :destroy so recalculating a show (which deletes line items) detaches it from
  # the run and re-totals it (see PayoutContribution#resettle_item_and_batch).
  has_one :payout_contribution, as: :source, dependent: :destroy

  # Payee types that carry a company-wide payout balance (guests do not).
  LEDGER_PAYEE_TYPES = %w[Person Contractor Group].freeze

  # Payment methods for tracking how payments were made. "stripe" is the internal
  # marker for a line paid through a payout run and "n/a" for $0 lines — both are
  # stored, never hand-picked. MANUAL_PAYMENT_METHODS is what a manager can choose
  # when recording an offline payment.
  PAYMENT_METHODS = %w[cash check zelle venmo other historical n/a stripe].freeze
  MANUAL_PAYMENT_METHODS = %w[cash check zelle venmo other historical].freeze

  # Payout statuses for tracking payment state
  PAYOUT_STATUSES = %w[pending success failed].freeze

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # Allow same person to have multiple line items if one is an individual allocation
  validates :payee_id, uniqueness: { scope: [ :show_payout_id, :payee_type, :is_individual_allocation ] }, if: -> { payee_id.present? }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validates :payout_status, inclusion: { in: PAYOUT_STATUSES }, allow_nil: true
  # Guests must have a name
  validates :guest_name, presence: true, if: :is_guest?
  # Non-guests must have a payee
  validates :payee, presence: true, unless: :is_guest?

  after_save :check_all_paid, if: -> { saved_change_to_manually_paid? || saved_change_to_payout_status? }

  scope :by_amount, -> { order(amount: :desc) }
  scope :by_name, -> { includes(:payee).sort_by { |li| li.payee.name } }
  scope :already_paid, -> { where(manually_paid: true) }
  scope :not_already_paid, -> { where(manually_paid: false, payout_reference_id: nil) }
  # The canonical paid/unpaid split (mirrors #paid?): manually marked paid OR
  # transferred via a Stripe payout run. The `already_paid`/`not_already_paid`
  # scopes above only see the manual case, so use these for money/people tallies.
  scope :paid, -> { where("manually_paid OR (payout_reference_id IS NOT NULL AND payout_status = 'success')") }
  scope :unpaid, -> { where("NOT manually_paid AND (payout_reference_id IS NULL OR payout_status IS DISTINCT FROM 'success')") }
  scope :paid_offline, -> { where(manually_paid: true) }
  scope :payout_pending, -> { where(payout_status: "pending") }
  scope :payout_failed, -> { where(payout_status: "failed") }
  scope :individual_allocations, -> { where(is_individual_allocation: true) }
  scope :performer_payouts, -> { where(is_individual_allocation: false, is_guest: false) }
  scope :guests, -> { where(is_guest: true) }

  def mark_as_already_paid!(by_user, method: nil, notes: nil)
    update!(
      manually_paid: true,
      manually_paid_at: Time.current,
      manually_paid_by: by_user,
      payment_method: method,
      payment_notes: notes,
      paid_at: Time.current
    )
    sync_payout_ledger_entry!
  end

  def mark_as_offline_paid!(by_user, method:, notes: nil)
    update!(
      manually_paid: true,
      manually_paid_at: Time.current,
      manually_paid_by: by_user,
      payment_method: method,
      payment_notes: notes,
      paid_at: Time.current
    )
    sync_payout_ledger_entry!
  end

  # Marked paid because its payout run's item was transferred via Stripe. Only
  # flips this line's display/traceability state — the run's PayoutBatchItem
  # posts the ledger payout, so we deliberately don't post another one here.
  def mark_paid_via_payout_run!(reference_id: nil)
    update!(
      payout_status: "success",
      payout_reference_id: reference_id,
      payment_method: "stripe",
      paid_at: Time.current
    )
  end

  def unmark_as_already_paid!
    # If payout was marked as paid, revert it to awaiting_payout
    if show_payout.paid?
      show_payout.revert_to_awaiting_payout!
    end

    update!(
      manually_paid: false,
      manually_paid_at: nil,
      manually_paid_by: nil,
      payment_method: nil,
      payment_notes: nil,
      paid_at: nil,
      payout_reference_id: nil,
      payout_status: nil,
      payout_error: nil
    )
    sync_payout_ledger_entry!
  end

  # Whether this line item participates in the company-wide payout ledger.
  def ledger_eligible?
    !is_guest? && payee_id.present? && LEDGER_PAYEE_TYPES.include?(payee_type)
  end

  # A bank-connected performer: they're paid through a Stripe payout run, not
  # hand-paid per show via Venmo/Zelle. Legacy performers (Venmo/Zelle/cash) are
  # unaffected. False until the payee connects a bank, so the existing per-show
  # pay flow is unchanged for everyone today. (Historically called "auto-pay",
  # but adding to a run is a manual step — see #in_payout_run?.)
  def auto_payout?
    return false if is_guest? || paid?
    return false unless payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?

    # Still awaiting a run — not yet covered by a completed payout.
    !settled_via_payout_run?
  end

  # Whether this line has actually been added to a payout run yet. Bank-connected
  # performers show a badge, but nothing moves until a manager clicks
  # "Add to payout run", so the badge must distinguish "ready to add" from "added".
  def in_payout_run?
    payout_contribution.present?
  end

  # A bank-connected performer whose balance has already been paid down by a
  # completed payout run. Their per-show line reads "Paid · payout run" instead
  # of forever showing "Auto-pay · next payout run".
  def settled_via_payout_run?
    return false if is_guest? || paid?
    return false unless ledger_eligible? && payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?

    org = show_payout&.production&.organization
    return false unless org

    org.payout_balance_cents_for(payee) <= 0 && paid_via_batch?(org)
  end

  # Post/refresh this line item's `earning` entry (net of advances) on the ledger.
  # Idempotent per line item. No-op for guests and non-ledger payees.
  def sync_earning_ledger_entry!
    return unless ledger_eligible?

    org = show_payout&.production&.organization
    return unless org

    PayoutLedgerEntry.post!(
      organization: org,
      payee: payee,
      entry_type: "earning",
      amount_cents: (net_amount.to_d * 100).round,
      source: self,
      description: "Show payout earning",
      occurred_at: show&.date_and_time || show_payout&.calculated_at || Time.current
    )
  end

  # Post a `payout` entry when this line item is paid (manually/offline), or
  # remove it when unpaid. Keeps the ledger balance in step with the paid state.
  def sync_payout_ledger_entry!
    return unless ledger_eligible?

    org = show_payout&.production&.organization
    return unless org

    if paid?
      PayoutLedgerEntry.post!(
        organization: org,
        payee: payee,
        entry_type: "payout",
        amount_cents: -(net_amount.to_d * 100).round,
        source: self,
        description: payment_method_label ? "Paid via #{payment_method_label}" : "Paid",
        occurred_at: paid_at || Time.current
      )
    else
      PayoutLedgerEntry.unpost!(source: self, entry_type: "payout")
    end
  end

  def paid?
    manually_paid? || (payout_reference_id.present? && payout_status == "success")
  end

  def payout_pending?
    payout_status == "pending"
  end

  def payout_failed?
    payout_status == "failed"
  end

  def paid_offline?
    manually_paid? && payment_method.present?
  end

  def payment_method_label
    return nil unless payment_method
    case payment_method
    when "cash" then "Cash"
    when "check" then "Check"
    when "zelle" then "Zelle"
    when "venmo" then "Venmo"
    when "historical" then "Historical"
    when "n/a" then "N/A"
    when "other" then "Other"
    when "stripe" then "CocoScout" # paid through a payout run — provider isn't user-facing
    else payment_method.titleize
    end
  end

  # Net amount after advance deductions
  def net_amount
    amount - (advance_deduction || 0)
  end

  # Check if this can be paid independently (for one-off payments)
  def can_pay_independently?
    !paid?
  end

  # Mark as paid independently (for one-off payments)
  def pay_independently!(by_user, method: nil, notes: nil)
    update!(paid_independently: true)
    mark_as_already_paid!(by_user, method: method, notes: notes)
  end

  # Calculation details accessors
  def calculation_breakdown
    calculation_details["breakdown"] || []
  end

  def calculation_formula
    calculation_details["formula"] || ""
  end

  def calculation_inputs
    calculation_details["inputs"] || {}
  end

  # Human-readable explanation of how amount was calculated
  def calculation_explanation
    return "Manual entry" if calculation_details.blank?

    formula = calculation_formula
    return formula if formula.present?

    # Build from breakdown
    breakdown = calculation_breakdown
    return "No calculation recorded" if breakdown.empty?

    breakdown.join(" → ")
  end

  # Payee display name
  def payee_name
    is_guest? ? guest_name : (payee&.name || "Unknown")
  end

  # Payee type label
  def payee_type_label
    return "Guest" if is_guest?
    return "Allocation" if is_individual_allocation?
    case payee_type
    when "Person" then "Individual"
    when "Group" then "Group"
    else payee_type
    end
  end

  private

  # Has a completed payout batch actually sent this payee money for this org?
  def paid_via_batch?(org)
    PayoutBatchItem.paid
                   .joins(:payout_batch)
                   .where(payout_batches: { organization_id: org.id })
                   .where(payee_type: payee.class.polymorphic_name, payee_id: payee_id)
                   .exists?
  end

  # Check if all line items are paid and auto-mark the show payout as paid
  def check_all_paid
    return unless paid? # Only check when marking as paid, not when unmarking

    # Reload show_payout to get fresh line_items count
    payout = show_payout.reload
    return if payout.paid? # Already paid

    # Check if all line items are now paid
    if payout.line_items.all?(&:paid?)
      # Directly update to paid status (skip the approval requirement for manual payments)
      payout.update!(status: "paid")
    end
  end
end

# frozen_string_literal: true

class ShowPayout < ApplicationRecord
  # Only two actual statuses: awaiting_payout (calculated, not all paid) and paid (all paid)
  STATUSES = %w[awaiting_payout paid].freeze

  belongs_to :show
  belongs_to :payout_scheme, optional: true

  has_one :production, through: :show
  has_one :show_financials, through: :show

  has_many :line_items, class_name: "ShowPayoutLineItem", dependent: :destroy

  validates :show_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # Migrate legacy statuses (draft, approved, etc.) to awaiting_payout
  before_validation :normalize_status

  scope :awaiting_payout, -> { where(status: "awaiting_payout") }
  scope :paid, -> { where(status: "paid") }
  scope :not_paid, -> { where.not(status: "paid") }

  # Get effective rules (override or scheme)
  def effective_rules
    override_rules.presence || payout_scheme&.rules || {}
  end

  # Check if using event-level overrides
  def has_overrides?
    override_rules.present?
  end

  # --- Act-based pay -------------------------------------------------------
  #
  # An act-based scheme can't be calculated from the show's data alone: someone
  # has to say how many acts each person did. Those counts live here (keyed by
  # payee) so they survive the line items being rebuilt on every recalculation.

  # The rules a calculation would actually run on: an event-level override, this
  # payout's scheme, or — when neither is set — the default scheme for the show.
  def resolved_rules
    override_rules.presence || (payout_scheme || PayoutScheme.default_for_show(show))&.rules || {}
  end

  def act_based?
    resolved_rules.dig("distribution", "method").to_s == "per_act"
  end

  # Stable key for one payee's act count: a cast member ("Person_12" /
  # "Group_3"), or a guest slot on the show ("guest_45", keyed by the
  # assignment because a guest has no record of their own).
  def self.act_key(payee)
    return "guest_#{payee.id}" if payee.is_a?(ShowPersonRoleAssignment)

    "#{payee.class.name}_#{payee.id}"
  end

  # The distribution config an act-based calculation runs on (rate or tiers).
  def act_distribution
    resolved_rules["distribution"] || {}
  end

  def act_count_for(payee)
    (act_counts || {})[self.class.act_key(payee)].to_i
  end

  # The payees an act-based calculation needs a count for: everyone assigned to
  # the show whose role isn't excluded by the scheme.
  def act_payees
    excluded_role_ids = Array(resolved_rules["excluded_role_ids"]).map(&:to_i)
    assignments = show.show_person_role_assignments.includes(:assignable, :role).to_a
    assignments = assignments.reject { |a| excluded_role_ids.include?(a.role_id) } if excluded_role_ids.any?

    people = assignments.reject(&:guest?).map(&:assignable).compact.uniq
    people + assignments.select(&:guest?)
  end

  # Status helpers
  def awaiting_payout?
    status == "awaiting_payout"
  end

  def paid?
    status == "paid"
  end

  # Derived statuses based on show financials state
  def awaiting_financials?
    !show.show_financials&.complete?
  end

  def awaiting_calculation?
    show.show_financials&.complete? && !calculated_at.present?
  end

  def can_edit?
    !paid?
  end

  def can_recalculate?
    !paid? && show.show_financials&.complete?
  end

  # Mark as paid (when all line items are paid)
  def mark_paid!
    update!(status: "paid")
    settle_contract_payment!
  end

  # Auto-settle the ContractPayment associated with this show, if one exists.
  # For per-event contracts: always settle. For weekly/monthly: only settle when
  # all shows in the period have been paid.
  def settle_contract_payment!(payment_method: nil, notes: nil)
    production = show.production
    return unless production.type_third_party?

    # A production can carry several contracts; the one that applies to THIS show is
    # the one that booked its space rental. Fall back to the production's latest.
    contract = show.space_rental&.contract || production.contract
    return unless contract&.revenue_share?

    contract_payment = contract.find_payment_for_show(show)
    return unless contract_payment&.status_pending?

    settlement = contract.draft_payment_config["revenue_settlement"] || "monthly"
    if %w[per_event next_day same_day].include?(settlement)
      contract_payment.mark_paid!(paid_on: Date.current, method: payment_method, reference: notes)
    else
      # For period-based settlements, only settle once all shows in the period are paid
      period_shows = contract.shows_for_payment(contract_payment)
      all_paid = period_shows.all? do |s|
        s.show_payout&.paid?
      end
      if all_paid
        contract_payment.mark_paid!(paid_on: Date.current, method: payment_method, reference: notes)
      end
    end
  rescue => e
    Rails.logger.warn("Could not settle contract payment for show #{show.id}: #{e.message}")
  end

  # Mark as awaiting payout (when calculated)
  def mark_awaiting_payout!
    update!(status: "awaiting_payout")
  end

  # Revert from paid to awaiting_payout (when unmarking a line item)
  def revert_to_awaiting_payout!
    return false unless paid?
    update!(status: "awaiting_payout")
  end

  # Calculate total from line items
  def recalculate_total!
    update!(total_payout: line_items.sum(:amount))
  end

  # Whether any of this show's payout lines have already been added to a
  # (performer) payout run.
  def in_payout_run?
    PayoutContribution.where(source_type: "ShowPayoutLineItem", source_id: line_items.select(:id)).exists?
  end

  # The specific (performer) payout run this show's payouts were added to, if any,
  # so we can link straight to it instead of the full list of runs.
  def payout_run
    PayoutContribution
      .where(source_type: "ShowPayoutLineItem", source_id: line_items.select(:id))
      .order(created_at: :desc)
      .first&.payout_batch
  end

  # Post/refresh each performer line item's `earning` entry on the payout ledger.
  # Idempotent (keyed per line item); called after a payout is calculated and by
  # the ledger backfill. Paid line items also carry an offsetting `payout` entry.
  def sync_earnings_to_ledger!
    line_items.includes(:payee).find_each do |li|
      li.sync_earning_ledger_entry!
      li.sync_payout_ledger_entry! if li.paid?
    end
  end

  # Total advance deductions from all line items
  def total_advance_deductions
    line_items.sum(:advance_deduction)
  end

  # Net total (what actually needs to be paid out)
  def total_net_payout
    (total_payout || 0) - total_advance_deductions
  end

  # Check if advance deductions are stale (out of sync with current advance state)
  # Returns true if:
  # 1. Line items show deductions but those advances are now settled (already recovered)
  # 2. There are outstanding advances for performers that aren't reflected in deductions
  # Advances are no longer deducted at calc time (they net on the payout ledger),
  # so there's nothing to be "stale" against.
  def advance_deductions_stale?
    false
  end

  # Display status - combines stored status with derived states
  def display_status
    return :paid if paid?
    return :awaiting_payout if awaiting_payout? || calculated_at.present?
    return :awaiting_calculation if awaiting_calculation?
    :awaiting_financials
  end

  def display_status_label
    case display_status
    when :awaiting_financials then "Awaiting Financials"
    when :awaiting_calculation then "Awaiting Calculation"
    when :awaiting_payout then "Awaiting Payout"
    when :paid then "Paid"
    end
  end

  def display_status_class
    case display_status
    when :awaiting_financials then "text-pink-600"
    when :awaiting_calculation then "text-gray-600"
    when :awaiting_payout then "text-pink-600"
    when :paid then "text-pink-600"
    end
  end

  private

  # Normalize legacy statuses (draft, approved, etc.) to valid statuses
  def normalize_status
    return if status.nil? || STATUSES.include?(status)

    # Any non-paid legacy status becomes awaiting_payout
    self.status = "awaiting_payout"
  end
end

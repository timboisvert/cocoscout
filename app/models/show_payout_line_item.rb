# frozen_string_literal: true

class ShowPayoutLineItem < ApplicationRecord
  belongs_to :show_payout
  belongs_to :payee, polymorphic: true, optional: true  # Person or Group (optional for guests)
  belongs_to :manually_paid_by, class_name: "User", optional: true

  has_one :show, through: :show_payout
  has_one :production, through: :show_payout

  # Payment methods for tracking how payments were made
  PAYMENT_METHODS = %w[venmo cash zelle check other historical n/a].freeze

  # Payout statuses for tracking payment state
  PAYOUT_STATUSES = %w[pending success failed].freeze

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :payee_id, uniqueness: { scope: [ :show_payout_id, :payee_type ] }, if: -> { payee_id.present? }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validates :payout_status, inclusion: { in: PAYOUT_STATUSES }, allow_nil: true
  # Guests must have a name
  validates :guest_name, presence: true, if: :is_guest?
  # Non-guests must have a payee
  validates :payee, presence: true, unless: :is_guest?

  after_save :check_all_paid, if: :saved_change_to_manually_paid?

  scope :by_amount, -> { order(amount: :desc) }
  scope :by_name, -> { includes(:payee).sort_by { |li| li.payee.name } }
  scope :already_paid, -> { where(manually_paid: true) }
  scope :not_already_paid, -> { where(manually_paid: false, payout_reference_id: nil) }
  scope :paid_via_venmo, -> { where(payment_method: "venmo").where.not(payout_reference_id: nil) }
  scope :paid_offline, -> { where(manually_paid: true) }
  scope :payout_pending, -> { where(payout_status: "pending") }
  scope :payout_failed, -> { where(payout_status: "failed") }

  def mark_as_already_paid!(by_user, method: nil, notes: nil)
    update!(
      manually_paid: true,
      manually_paid_at: Time.current,
      manually_paid_by: by_user,
      payment_method: method,
      payment_notes: notes,
      paid_at: Time.current
    )
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
  end

  def paid?
    manually_paid? || (payout_reference_id.present? && payout_status == "success")
  end

  def paid_via_venmo?
    return false unless payment_method == "venmo"
    # Paid via automated Venmo payout OR manually marked as paid via Venmo
    (payout_reference_id.present? && payout_status == "success") || manually_paid?
  end

  def paid_via_zelle?
    return false unless payment_method == "zelle"
    # Manually marked as paid via Zelle (no automated Zelle, so just check manually_paid)
    manually_paid?
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
    when "venmo" then "Venmo"
    when "cash" then "Cash"
    when "zelle" then "Zelle"
    when "check" then "Check"
    when "historical" then "Historical"
    when "n/a" then "N/A"
    when "other" then "Other"
    else payment_method.titleize
    end
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
    case payee_type
    when "Person" then "Individual"
    when "Group" then "Group"
    else payee_type
    end
  end

  # Guest payment methods
  def guest_venmo_configured?
    is_guest? && guest_venmo.present?
  end

  def guest_zelle_configured?
    is_guest? && guest_zelle.present?
  end

  def guest_has_payment_method?
    guest_venmo_configured? || guest_zelle_configured?
  end

  # Get guest's preferred payment info
  def guest_preferred_payment
    return nil unless is_guest?
    if guest_venmo.present?
      { method: "venmo", identifier: guest_venmo }
    elsif guest_zelle.present?
      { method: "zelle", identifier: guest_zelle }
    end
  end

  # Override payee_has_payment_method? to handle guests
  def payee_has_payment_method?
    if is_guest?
      guest_has_payment_method?
    else
      payee_venmo_ready? || payee_zelle_ready?
    end
  end

  # Override payee_venmo_ready? to handle guests
  def payee_venmo_ready?
    if is_guest?
      guest_venmo_configured?
    else
      return false unless payee.respond_to?(:venmo_ready_for_payouts?)
      payee.venmo_ready_for_payouts?
    end
  end

  # Override payee_zelle_ready? to handle guests
  def payee_zelle_ready?
    if is_guest?
      guest_zelle_configured?
    else
      return false unless payee.respond_to?(:zelle_ready_for_payouts?)
      payee.zelle_ready_for_payouts?
    end
  end

  # Get payee's preferred payment info (handles both guests and regular payees)
  def payee_preferred_payment
    if is_guest?
      guest_preferred_payment
    else
      return nil unless payee.respond_to?(:preferred_payment_info)
      payee.preferred_payment_info
    end
  end

  private

  # Check if all line items are paid and auto-mark the show payout as paid
  def check_all_paid
    return unless manually_paid? # Only check when marking as paid, not when unmarking

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

# frozen_string_literal: true

class ShowPayoutLineItem < ApplicationRecord
  belongs_to :show_payout
  belongs_to :payee, polymorphic: true  # Person or Group
  belongs_to :manually_paid_by, class_name: "User", optional: true

  has_one :show, through: :show_payout
  has_one :production, through: :show_payout

  # Payment methods for offline payments
  PAYMENT_METHODS = %w[stripe cash venmo zelle check paypal other historical].freeze

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :payee_id, uniqueness: { scope: [ :show_payout_id, :payee_type ] }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true

  scope :by_amount, -> { order(amount: :desc) }
  scope :by_name, -> { includes(:payee).sort_by { |li| li.payee.name } }
  scope :already_paid, -> { where(manually_paid: true) }
  scope :not_already_paid, -> { where(manually_paid: false) }
  scope :paid_via_stripe, -> { where(payment_method: "stripe") }
  scope :paid_offline, -> { where.not(payment_method: [ nil, "stripe" ]) }

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
    update!(
      manually_paid: false,
      manually_paid_at: nil,
      manually_paid_by: nil,
      payment_method: nil,
      payment_notes: nil,
      paid_at: nil,
      stripe_transfer_id: nil
    )
  end

  def paid?
    manually_paid? || stripe_transfer_id.present?
  end

  def paid_via_stripe?
    payment_method == "stripe" && stripe_transfer_id.present?
  end

  def paid_offline?
    manually_paid? && payment_method.present? && payment_method != "stripe"
  end

  def payment_method_label
    return nil unless payment_method
    case payment_method
    when "stripe" then "Stripe"
    when "cash" then "Cash"
    when "venmo" then "Venmo"
    when "zelle" then "Zelle"
    when "check" then "Check"
    when "paypal" then "PayPal"
    when "historical" then "Historical"
    when "other" then "Other"
    else payment_method.titleize
    end
  end

  # Check if payee can receive Stripe payments
  def payee_stripe_ready?
    return false unless payee.respond_to?(:stripe_ready_for_payouts?)
    payee.stripe_ready_for_payouts?
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
    payee&.name || "Unknown"
  end

  # Payee type label
  def payee_type_label
    case payee_type
    when "Person" then "Individual"
    when "Group" then "Group"
    else payee_type
    end
  end
end

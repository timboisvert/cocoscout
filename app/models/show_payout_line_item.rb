# frozen_string_literal: true

class ShowPayoutLineItem < ApplicationRecord
  belongs_to :show_payout
  belongs_to :payee, polymorphic: true  # Person or Group
  belongs_to :manually_paid_by, class_name: "User", optional: true

  has_one :show, through: :show_payout
  has_one :production, through: :show_payout

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :payee_id, uniqueness: { scope: [ :show_payout_id, :payee_type ] }

  scope :by_amount, -> { order(amount: :desc) }
  scope :by_name, -> { includes(:payee).sort_by { |li| li.payee.name } }
  scope :already_paid, -> { where(manually_paid: true) }
  scope :not_already_paid, -> { where(manually_paid: false) }

  def mark_as_already_paid!(by_user)
    update!(manually_paid: true, manually_paid_at: Time.current, manually_paid_by: by_user)
  end

  def unmark_as_already_paid!
    update!(manually_paid: false, manually_paid_at: nil, manually_paid_by: nil)
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

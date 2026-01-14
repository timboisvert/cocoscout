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
end

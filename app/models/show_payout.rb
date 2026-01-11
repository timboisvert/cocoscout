# frozen_string_literal: true

class ShowPayout < ApplicationRecord
  STATUSES = %w[draft approved paid].freeze

  belongs_to :show
  belongs_to :payout_scheme, optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  has_one :production, through: :show
  has_one :show_financials, through: :show

  has_many :line_items, class_name: "ShowPayoutLineItem", dependent: :destroy

  validates :show_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :drafts, -> { where(status: "draft") }
  scope :approved, -> { where(status: "approved") }
  scope :paid, -> { where(status: "paid") }
  scope :not_draft, -> { where.not(status: "draft") }

  # Get effective rules (override or scheme)
  def effective_rules
    override_rules.presence || payout_scheme&.rules || {}
  end

  # Check if using event-level overrides
  def has_overrides?
    override_rules.present?
  end

  # Status helpers
  def draft?
    status == "draft"
  end

  def approved?
    status == "approved"
  end

  def paid?
    status == "paid"
  end

  def can_edit?
    draft?
  end

  def can_approve?
    draft? && line_items.any?
  end

  def can_mark_paid?
    approved?
  end

  # Approve the payout (locks it)
  def approve!(user)
    return false unless can_approve?

    update!(
      status: "approved",
      approved_at: Time.current,
      approved_by: user
    )
  end

  # Mark as paid
  def mark_paid!
    return false unless can_mark_paid?

    update!(status: "paid")
  end

  # Revert to draft (for corrections)
  def revert_to_draft!
    return false if paid?

    update!(
      status: "draft",
      approved_at: nil,
      approved_by: nil
    )
  end

  # Calculate total from line items
  def recalculate_total!
    update!(total_payout: line_items.sum(:amount))
  end

  # Summary for display
  def status_badge_class
    case status
    when "draft" then "bg-gray-100 text-gray-700"
    when "approved" then "bg-green-100 text-green-700"
    when "paid" then "bg-pink-100 text-pink-700"
    end
  end

  def status_label
    status.capitalize
  end
end

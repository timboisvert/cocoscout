# frozen_string_literal: true

class CourseOfferingPayout < ApplicationRecord
  STATUSES = %w[pending calculated paid].freeze
  PAYOUT_MODES = %w[lump_sum per_session].freeze
  PAYMENT_METHODS = %w[venmo cash zelle check other].freeze

  belongs_to :course_offering

  has_many :line_items, class_name: "CourseOfferingPayoutLineItem", dependent: :destroy
  has_one :production, through: :course_offering
  has_one :contract, through: :course_offering

  validates :course_offering_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :payout_mode, inclusion: { in: PAYOUT_MODES }

  scope :pending, -> { where(status: "pending") }
  scope :calculated, -> { where(status: "calculated") }
  scope :paid, -> { where(status: "paid") }

  def pending?
    status == "pending"
  end

  def calculated?
    status == "calculated"
  end

  def paid?
    status == "paid"
  end

  def can_calculate?
    !paid? && course_offering.course_registrations.confirmed.any?
  end

  def can_recalculate?
    calculated? && line_items.where(manually_paid: true).none?
  end

  # Effective revenue: override if set, otherwise from registrations
  def effective_revenue_cents
    total_revenue_override_cents.presence || total_revenue_cents || 0
  end

  def mark_paid!
    update!(status: "paid", paid_at: Time.current)
  end

  def all_line_items_paid?
    line_items.any? && line_items.all? { |li| li.paid? }
  end

  def formatted_total_revenue
    format_cents(effective_revenue_cents)
  end

  def formatted_platform_fee
    format_cents(platform_fee_cents)
  end

  def formatted_net_revenue
    format_cents(net_revenue_cents)
  end

  def formatted_total_payout
    format_cents(total_payout_cents)
  end

  private

  def format_cents(cents)
    return "$0" if cents.nil? || cents.zero?
    dollars = cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end
end

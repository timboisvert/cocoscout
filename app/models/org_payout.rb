# frozen_string_literal: true

class OrgPayout < ApplicationRecord
  STATUSES = %w[pending paid].freeze
  PAYOUT_TYPES = %w[full_course per_session custom].freeze
  PAYMENT_METHODS = %w[venmo zelle cash check bank_transfer other].freeze

  belongs_to :organization
  belongs_to :course_offering, optional: true
  belongs_to :paid_by_user, class_name: "User", optional: true

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :status, inclusion: { in: STATUSES }
  validates :payout_type, inclusion: { in: PAYOUT_TYPES }

  scope :pending, -> { where(status: "pending") }
  scope :paid, -> { where(status: "paid") }
  scope :for_course, ->(course_offering) { where(course_offering: course_offering) }

  def pending?
    status == "pending"
  end

  def paid?
    status == "paid"
  end

  def mark_paid!(user:)
    update!(status: "paid", paid_at: Time.current, paid_by_user: user)
  end

  def formatted_amount
    return "$0" if amount_cents.nil? || amount_cents.zero?
    dollars = amount_cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end

  # Calculate what CocoScout owes an org for a specific course offering,
  # respecting promo code coverage types:
  #   - no promo: org gets 95% (5% CocoScout fee)
  #   - coverage_type "full": org gets 100% (all fees waived)
  #   - coverage_type "platform_only": org gets gross minus actual Stripe fees
  def self.owed_cents_for_course(course_offering)
    gross = course_offering.course_registrations.confirmed.sum(:amount_cents)
    coverage = course_offering.feature_credit_redemption&.feature_credit&.coverage_type

    case coverage
    when "full"
      gross
    when "platform_only"
      stripe_fees = course_offering.course_registrations.confirmed.sum(:stripe_fee_cents)
      gross - stripe_fees
    else
      (gross * 0.95).round
    end
  end

  def self.paid_cents_for_course(course_offering)
    paid.for_course(course_offering).sum(:amount_cents)
  end

  def self.balance_cents_for_course(course_offering)
    owed_cents_for_course(course_offering) - paid_cents_for_course(course_offering)
  end
end

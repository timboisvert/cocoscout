# frozen_string_literal: true

class OrgPayout < ApplicationRecord
  STATUSES = %w[pending paid].freeze
  PAYOUT_TYPES = %w[full_course per_session custom].freeze
  PAYMENT_METHODS = %w[cash check bank_transfer other].freeze

  belongs_to :organization
  belongs_to :course_offering, optional: true
  belongs_to :paid_by_user, class_name: "User", optional: true

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :status, inclusion: { in: STATUSES }
  validates :payout_type, inclusion: { in: PAYOUT_TYPES }

  # A payment recorded by hand in superadmin (paid_by_user set) was CocoScout
  # paying the theater outside Stripe: what CocoScout holds for it goes down
  # by that much (and CocoScout's ledger takes the Stripe money it leaves
  # behind, via the cash entry). Payouts a course run made have no
  # paid_by_user: that money left by transfer, already on the ledger.
  after_commit :sync_cash_entry

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

  def paid_by_hand?
    paid? && paid_by_user_id.present?
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
  #   - no promo: org gets gross minus the CocoScout fee (PLATFORM_FEE_PERCENTAGE, currently 10%)
  #   - coverage_type "full": org gets 100% (all fees waived)
  #   - coverage_type "platform_only": org gets gross minus actual Stripe fees
  def self.owed_cents_for_course(course_offering)
    confirmed = course_offering.course_registrations.confirmed
    gross = confirmed.sum(:amount_cents)
    # Tax collected on the registrations is the org's to remit: it's owed in full.
    tax = confirmed.sum(:tax_cents)
    coverage = course_offering.feature_credit_redemption&.feature_credit&.coverage_type

    case coverage
    when "full"
      gross + tax
    when "platform_only"
      stripe_fees = confirmed.sum(:stripe_fee_cents)
      gross - stripe_fees + tax
    else
      # Subtract the CocoScout fee ACTUALLY charged on each registration (stored
      # per row), not a re-computed rate — mirrors CoursePayoutCalculator, and
      # stays right for registrations charged under an older rate.
      gross - confirmed.sum(:cocoscout_fee_cents) + tax
    end
  end

  def self.paid_cents_for_course(course_offering)
    paid.for_course(course_offering).sum(:amount_cents)
  end

  def self.balance_cents_for_course(course_offering)
    owed_cents_for_course(course_offering) - paid_cents_for_course(course_offering)
  end

  private

  def sync_cash_entry
    if destroyed? || !paid_by_hand?
      OrgCashEntry.unpost!(source: self, entry_type: "adjustment")
    else
      OrgCashEntry.post!(organization: organization, entry_type: "adjustment", amount_cents: -amount_cents, source: self,
                         description: "Org payout ##{id} settled outside Stripe", occurred_at: paid_at || updated_at)
    end
  end
end

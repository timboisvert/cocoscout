# frozen_string_literal: true

class CourseOfferingPayout < ApplicationRecord
  STATUSES = %w[pending calculated paid].freeze
  PAYOUT_MODES = %w[lump_sum per_session].freeze
  PAYMENT_METHODS = %w[cash check bank_transfer other].freeze

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

  def can_recalculate?
    !pending?
  end

  # Effective revenue: override if set, otherwise from registrations
  def effective_revenue_cents
    total_revenue_override_cents.presence || total_revenue_cents || 0
  end

  def mark_paid!
    update!(status: "paid", paid_at: Time.current)
  end

  # Settle the payout once every line is actually paid. A payout with no
  # instructor lines is settled by its org row alone.
  def settle_if_fully_paid!
    return if paid?

    update_columns(status: "paid", paid_at: Time.current) if line_items.reload.all?(&:paid?)
  end

  # This payout is the SOURCE of the org's own remainder row on the payout run
  # (see CoursePayoutSettlement#org_row). Called when that run pays the org
  # (PayoutBatchService.settle_item_sources!): record the OrgPayout — the books'
  # record that CocoScout remitted the org its course share — and settle.
  def mark_paid_via_payout_run!(reference_id: nil)
    org_share = CoursePayoutSettlement.new(self).org_keeps_cents
    if org_share.positive?
      OrgPayout.create!(
        organization: course_offering.production.organization,
        course_offering: course_offering,
        amount_cents: org_share,
        status: "paid",
        payout_type: "full_course",
        payment_method: "bank_transfer",
        paid_at: Time.current
      )
    end
    settle_if_fully_paid!
  end

  # The run that paid the org's remainder came back — undo only what the run
  # itself recorded.
  def mark_unpaid_via_payout_run!
    update_columns(status: "calculated", paid_at: nil) if paid?
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

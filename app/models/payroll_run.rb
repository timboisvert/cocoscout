# frozen_string_literal: true

class PayrollRun < ApplicationRecord
  STATUSES = %w[pending processing completed cancelled].freeze

  belongs_to :organization
  belongs_to :payroll_schedule, optional: true  # Nullable for ad-hoc runs
  belongs_to :created_by, class_name: "User"
  belongs_to :processed_by, class_name: "User", optional: true

  has_many :payroll_line_items, dependent: :destroy
  has_many :people, through: :payroll_line_items
  has_many :show_payout_line_items, through: :payroll_line_items

  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :period_end_after_start

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: %w[pending processing]) }
  scope :by_period, -> { order(period_end: :desc) }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def cancelled?
    status == "cancelled"
  end

  def can_process?
    pending? && payroll_line_items.any?
  end

  def can_cancel?
    pending?
  end

  def period_label
    if period_start.month == period_end.month && period_start.year == period_end.year
      "#{period_start.strftime('%b %-d')} – #{period_end.strftime('%-d, %Y')}"
    else
      "#{period_start.strftime('%b %-d, %Y')} – #{period_end.strftime('%b %-d, %Y')}"
    end
  end

  # Build line items from unpaid ShowPayoutLineItems in the period
  # This links show payout line items to people, but does NOT pre-calculate amounts
  def build_line_items!
    return false unless pending?

    # Find unpaid show payout line items across ALL productions in this organization
    # Exclude those already in a payroll run or paid independently
    production_ids = organization.productions.where(production_type: :in_house).pluck(:id)

    eligible_items = ShowPayoutLineItem
      .joins(show_payout: :show)
      .where(shows: { production_id: production_ids })
      .where(shows: { date_and_time: period_start.beginning_of_day..period_end.end_of_day })
      .where(manually_paid: false)
      .where(payout_reference_id: nil)
      .where(payroll_line_item_id: nil)
      .where(paid_independently: false)
      .includes(:payee, show_payout: :show)

    # Group by person (skip guests for now - they're paid per-show)
    items_by_person = eligible_items.reject(&:is_guest?).group_by(&:payee)

    transaction do
      items_by_person.each do |person, line_items|
        next unless person.is_a?(Person)

        # Create payroll line item - amounts are calculated dynamically, not stored
        pli = payroll_line_items.create!(
          person: person,
          show_count: line_items.count
        )

        # Link the show payout line items to this payroll line item
        line_items.each { |li| li.update!(payroll_line_item: pli) }
      end

      # Update summary counts (these are for display only, actual amounts are dynamic)
      update!(
        line_item_count: payroll_line_items.count
      )
    end

    true
  end

  # Calculate total amount dynamically from linked show payout line items
  def calculated_total_amount
    payroll_line_items.sum(&:net_amount)
  end

  # Mark the run as completed (all payments made)
  def complete!
    return false unless processing? || pending?

    update!(
      status: "completed",
      processed_at: Time.current,
      processed_by: processed_by
    )
  end

  # Mark as processing (payments in progress)
  def start_processing!(by_user)
    return false unless pending?

    update!(
      status: "processing",
      processed_by: by_user
    )
  end

  # Cancel the run
  def cancel!
    return false unless pending?

    transaction do
      # Unlink all show payout line items
      show_payout_line_items.update_all(payroll_line_item_id: nil)
      payroll_line_items.destroy_all
      update!(status: "cancelled")
    end

    true
  end

  private

  def period_end_after_start
    return unless period_start && period_end

    if period_end < period_start
      errors.add(:period_end, "must be after period start")
    end
  end
end

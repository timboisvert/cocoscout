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

  # Build line items from unpaid ShowPayoutLineItems
  # Includes the current period PLUS any unpaid items from previous periods
  def build_line_items!
    return false unless pending?

    # Find unpaid show payout line items across ALL productions in this organization
    # Exclude those already in a payroll run or paid independently
    production_ids = organization.productions.where(production_type: :in_house).pluck(:id)

    # Include items from current period AND any unpaid items from before this period
    # (up to the end of the current period)
    eligible_items = ShowPayoutLineItem
      .joins(show_payout: :show)
      .where(shows: { production_id: production_ids })
      .where("shows.date_and_time <= ?", period_end.end_of_day)
      .where(manually_paid: false)
      .where(payout_reference_id: nil)
      .where(payroll_line_item_id: nil)
      .where(paid_independently: false)
      .includes(show_payout: :show)

    # Group by person (skip guests for now - they're paid per-show)
    items_by_person = eligible_items.reject(&:is_guest?).group_by(&:payee)

    transaction do
      items_by_person.each do |person, line_items|
        next unless person.is_a?(Person)

        # Apply outstanding advances to these line items
        apply_advances_to_line_items!(person, line_items)

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
    return false unless pending? || processing?

    transaction do
      # Revert advance deductions - restore remaining_balance on PersonAdvances
      show_payout_line_items.each do |spli|
        spli.advance_recoveries.each do |recovery|
          advance = recovery.person_advance
          advance.update!(
            remaining_balance: advance.remaining_balance + recovery.amount,
            status: advance.remaining_balance + recovery.amount >= advance.original_amount ? "pending" : "partial",
            fully_recovered_at: nil
          )
        end
        # Clear the advance_deduction on the line item
        spli.update!(advance_deduction: 0) if spli.advance_deduction.to_f > 0
      end

      # Unlink all show payout line items
      show_payout_line_items.update_all(payroll_line_item_id: nil)
      payroll_line_items.destroy_all
      update!(status: "cancelled")
    end

    true
  end

  private

  # Apply outstanding advances to show payout line items for a person
  # This deducts advances from their payout amounts at payroll time
  def apply_advances_to_line_items!(person, line_items)
    # Get outstanding advances for this person across all productions in the org
    production_ids = organization.productions.where(production_type: :in_house).pluck(:id)

    advances = person.person_advances
      .where(production_id: production_ids)
      .outstanding
      .paid  # Only apply advances that have been paid out to the person
      .order(:issued_at)  # Oldest first

    return if advances.empty?

    # Sort line items by show date (oldest first) to apply advances chronologically
    sorted_items = line_items.sort_by { |li| li.show_payout.show.date_and_time }

    advances.each do |advance|
      break if advance.remaining_balance <= 0

      sorted_items.each do |line_item|
        break if advance.remaining_balance <= 0

        # Calculate how much of this line item's amount is available for deduction
        # (after any existing deductions)
        available_amount = line_item.amount - (line_item.advance_deduction || 0)
        next if available_amount <= 0

        # Apply the advance
        actual_deduction = advance.apply!(available_amount, line_item)

        # Update the line item's advance_deduction
        if actual_deduction > 0
          new_deduction = (line_item.advance_deduction || 0) + actual_deduction
          line_item.update!(advance_deduction: new_deduction)
        end
      end
    end
  end

  def period_end_after_start
    return unless period_start && period_end

    if period_end < period_start
      errors.add(:period_end, "must be after period start")
    end
  end
end

# frozen_string_literal: true

class PayrollLineItem < ApplicationRecord
  PAYMENT_METHODS = %w[venmo cash zelle check other].freeze
  PAYOUT_STATUSES = %w[pending success failed].freeze

  belongs_to :payroll_run
  belongs_to :person
  belongs_to :manually_paid_by, class_name: "User", optional: true

  has_many :show_payout_line_items, dependent: :nullify
  has_one :organization, through: :payroll_run

  validates :person_id, uniqueness: { scope: :payroll_run_id }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validates :payout_status, inclusion: { in: PAYOUT_STATUSES }, allow_nil: true

  scope :by_name, -> { includes(:person).order("people.name") }
  scope :paid, -> { where(manually_paid: true).or(where(payout_status: "success")) }
  scope :unpaid, -> { where(manually_paid: false).where.not(payout_status: "success") }

  # Calculate amounts dynamically from linked show payout line items
  # This ensures we always have current amounts even if they change
  def gross_amount
    show_payout_line_items.sum(:amount)
  end

  def advance_deductions
    show_payout_line_items.sum(:advance_deduction)
  end

  def net_amount
    gross_amount - advance_deductions
  end

  def show_count
    show_payout_line_items.count
  end

  # Build a breakdown of shows for display
  def breakdown
    show_payout_line_items.includes(show_payout: :show).map do |spli|
      show = spli.show_payout.show
      {
        show_id: show.id,
        show_date: show.date_and_time,
        show_name: show.display_name,
        production_name: show.production.name,
        amount: spli.amount.to_f,
        advance_deduction: spli.advance_deduction.to_f
      }
    end
  end

  def paid?
    manually_paid? || payout_status == "success"
  end

  def mark_as_paid!(by_user, method: nil, notes: nil)
    update!(
      manually_paid: true,
      manually_paid_at: Time.current,
      manually_paid_by: by_user,
      payment_method: method,
      payment_notes: notes,
      paid_at: Time.current
    )

    # Also mark all associated show payout line items as paid
    show_payout_line_items.each do |spli|
      spli.mark_as_already_paid!(by_user, method: method, notes: "Paid via payroll run ##{payroll_run_id}")
    end

    # Check if all line items in the run are paid
    check_run_complete
  end

  def unmark_as_paid!
    update!(
      manually_paid: false,
      manually_paid_at: nil,
      manually_paid_by: nil,
      payment_method: nil,
      payment_notes: nil,
      paid_at: nil,
      payout_reference_id: nil,
      payout_status: nil,
      payout_error: nil
    )

    # Also unmark associated show payout line items
    show_payout_line_items.each(&:unmark_as_already_paid!)
  end

  private

  def check_run_complete
    return unless payroll_run.processing?

    if payroll_run.payroll_line_items.all?(&:paid?)
      payroll_run.complete!
    end
  end
end

# frozen_string_literal: true

class ContractPayment < ApplicationRecord
  belongs_to :contract

  # Direction: whether they pay us or we pay them
  enum :direction, {
    incoming: "incoming",  # They pay us (rental fee, deposit)
    outgoing: "outgoing"   # We pay them (services, reimbursements)
  }, prefix: :direction

  # Payment status
  enum :status, {
    pending: "pending",
    paid: "paid",
    overdue: "overdue",
    cancelled: "cancelled"
  }, default: :pending, prefix: :status

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than: 0 }, unless: :amount_tbd?
  validates :due_date, presence: true
  validates :direction, presence: true

  scope :upcoming, -> { status_pending.where("due_date >= ?", Date.current).order(:due_date) }
  scope :overdue, -> { status_pending.where("due_date < ?", Date.current).order(:due_date) }
  scope :by_due_date, -> { order(:due_date) }

  # Check if payment amount is to be determined (e.g., revenue share)
  def amount_tbd?
    amount_tbd
  end

  # Check if this is a revenue share payment (amount determined after events)
  def revenue_share?
    description&.downcase&.include?("revenue share")
  end

  # Check if payment is overdue
  def overdue?
    status_pending? && due_date < Date.current
  end

  # Mark as paid
  def mark_paid!(paid_on: Date.current, method: nil, reference: nil)
    update!(
      status: :paid,
      paid_date: paid_on,
      payment_method: method,
      reference_number: reference
    )
  end

  # Display helpers
  def formatted_amount
    prefix = direction_incoming? ? "+" : "-"
    "#{prefix}$#{'%.2f' % amount}"
  end

  def status_badge_class
    case status
    when "paid" then "badge-success"
    when "pending" then overdue? ? "badge-danger" : "badge-warning"
    when "overdue" then "badge-danger"
    when "cancelled" then "badge-secondary"
    else "badge-secondary"
    end
  end
end

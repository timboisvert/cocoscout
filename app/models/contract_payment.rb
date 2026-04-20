# frozen_string_literal: true

class ContractPayment < ApplicationRecord
  belongs_to :contract
  belongs_to :show, optional: true

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

  # Check if this payment amount is to be determined (e.g., revenue share)
  def amount_tbd?
    amount_tbd
  end

  # Find linked CourseOfferingPayoutLineItem if this is an outgoing payment
  def linked_payout_line_item
    return nil unless direction_outgoing? && contract

    # Find course offerings for this contract
    course_offerings = contract.course_offerings
    return nil if course_offerings.empty?

    # Find line items in payouts from these course offerings
    CourseOfferingPayoutLineItem
      .joins(course_offering_payout: :course_offering)
      .where(course_offering_payout: { course_offering_id: course_offerings.ids })
      .where(payee_type: "Contractor", payee_id: contract.contractor_id)
      .where(manually_paid: true)
      .order(paid_at: :desc)
      .first
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
  def mark_paid!(paid_on: Date.current, method: nil, reference: nil, amount: nil)
    attrs = {
      status: :paid,
      paid_date: paid_on,
      payment_method: method,
      reference_number: reference
    }
    if amount.present?
      attrs[:amount] = amount.to_f
      attrs[:amount_tbd] = false
    end
    update!(attrs)
  end

  # Display helpers
  def formatted_amount
    prefix = direction_incoming? ? "+" : "-"
    "#{prefix}$#{'%.2f' % amount}"
  end

  # Compute a suggested amount based on contract terms and show financials.
  # Returns { amount: Float, explanation: String, shows: [...] } or nil.
  def suggested_amount_from_financials
    return nil unless amount_tbd? && contract

    linked_shows = contract.shows_for_payment(self)
    shows_with_data = linked_shows.select { |s| s.show_financials&.has_data? }
    return nil if shows_with_data.empty?

    total_revenue = shows_with_data.sum { |s| s.show_financials.total_revenue }
    config = contract.draft_payment_config
    structure = contract.draft_payment_structure

    suggested = case structure
    when "revenue_share"
      pct = direction_incoming? ? config["revenue_our_share"].to_f : config["revenue_their_share"].to_f
      calculated = (total_revenue * pct / 100.0).round(2)
      { amount: calculated, explanation: "#{pct.round(0)}% of revenue" }
    when "per_event"
      per_event_amt = config["per_event_amount"].to_f
      if per_event_amt > 0
        { amount: per_event_amt * linked_shows.size, explanation: "$#{'%.2f' % per_event_amt} per event" }
      end
    when "flat_fee"
      flat_amt = config["flat_fee_amount"].to_f
      fee_direction = config["flat_fee_direction"]
      if fee_direction == "ticket_revenue_minus_fee" && flat_amt > 0
        contractor_amount = (total_revenue - flat_amt).round(2)
        contractor_amount = [ contractor_amount, 0 ].max
        { amount: contractor_amount, explanation: "Ticket revenue minus $#{'%.2f' % flat_amt} fee" }
      elsif flat_amt > 0
        { amount: flat_amt, explanation: "Flat fee" }
      end
    end

    if suggested
      suggested[:shows] = shows_with_data
      suggested[:total_revenue] = total_revenue
    end

    suggested
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

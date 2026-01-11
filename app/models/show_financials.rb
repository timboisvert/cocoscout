# frozen_string_literal: true

class ShowFinancials < ApplicationRecord
  belongs_to :show

  has_one :production, through: :show

  validates :show_id, uniqueness: true
  validates :ticket_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :ticket_revenue, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :other_revenue, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expenses, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Total revenue from all sources
  def total_revenue
    (ticket_revenue || 0) + (other_revenue || 0)
  end

  # Net revenue after expenses
  def net_revenue
    total_revenue - (expenses || 0)
  end

  # Average ticket price (if any tickets sold)
  def average_ticket_price
    return 0 if ticket_count.nil? || ticket_count.zero?
    (ticket_revenue || 0) / ticket_count
  end

  # Check if we have enough data to calculate payouts
  def complete?
    ticket_count.present? && ticket_revenue.present?
  end

  # Check if data has been entered (not just defaults)
  def has_data?
    ticket_count.to_i > 0 || ticket_revenue.to_f > 0 || other_revenue.to_f > 0
  end
end

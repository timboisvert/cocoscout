# frozen_string_literal: true

class ShowFinancials < ApplicationRecord
  belongs_to :show

  has_one :production, through: :show

  REVENUE_TYPES = %w[ticket_sales flat_fee].freeze

  validates :show_id, uniqueness: true
  validates :revenue_type, inclusion: { in: REVENUE_TYPES }, allow_nil: true
  validates :ticket_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :ticket_revenue, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :flat_fee, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :other_revenue, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expenses, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Revenue type helpers
  def ticket_sales?
    revenue_type.nil? || revenue_type == "ticket_sales"
  end

  def flat_fee?
    revenue_type == "flat_fee"
  end

  # Primary revenue based on type
  def primary_revenue
    if flat_fee?
      flat_fee || 0
    else
      ticket_revenue || 0
    end
  end

  # Calculate other revenue from details if present, otherwise use stored amount
  def calculated_other_revenue
    if other_revenue_details.present? && other_revenue_details.any?
      other_revenue_details.sum { |item| item["amount"].to_f }
    else
      other_revenue || 0
    end
  end

  # Calculate expenses from details if present, otherwise use stored amount
  def calculated_expenses
    if expense_details.is_a?(Array) && expense_details.any?
      expense_details.sum do |item|
        if item.is_a?(Hash)
          item["amount"].to_f
        elsif item.is_a?(String)
          # Handle case where item is a JSON string
          parsed = JSON.parse(item) rescue nil
          parsed.is_a?(Hash) ? parsed["amount"].to_f : 0
        else
          0
        end
      end
    else
      expenses || 0
    end
  end

  # Total revenue from all sources
  def total_revenue
    primary_revenue + calculated_other_revenue
  end

  # Net revenue after expenses
  def net_revenue
    total_revenue - calculated_expenses
  end

  # Average ticket price (if any tickets sold)
  def average_ticket_price
    return 0 if ticket_count.nil? || ticket_count.zero?
    (ticket_revenue || 0) / ticket_count
  end

  # Check if we have enough data to calculate payouts
  def complete?
    # If user explicitly confirmed the data is complete, trust that
    return true if data_confirmed?

    if flat_fee?
      flat_fee.present? && flat_fee > 0
    else
      # For ticket sales, we need at least ticket revenue (count can be 0 for free shows)
      ticket_revenue.present? && ticket_revenue >= 0
    end
  end

  # Check if data has been entered (not just defaults)
  def has_data?
    data_confirmed? ||
      (flat_fee? && flat_fee.to_f > 0) ||
      ticket_count.to_i > 0 ||
      ticket_revenue.to_f > 0 ||
      calculated_other_revenue > 0 ||
      calculated_expenses > 0
  end

  # Add a revenue line item
  def add_other_revenue_item(description:, amount:)
    self.other_revenue_details ||= []
    self.other_revenue_details << { "description" => description, "amount" => amount.to_f }
  end

  # Add an expense line item
  def add_expense_item(description:, amount:)
    self.expense_details ||= []
    self.expense_details << { "description" => description, "amount" => amount.to_f }
  end
end

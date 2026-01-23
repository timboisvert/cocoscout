# frozen_string_literal: true

class ShowFinancials < ApplicationRecord
  belongs_to :show

  has_one :production, through: :show
  has_many :expense_items, -> { ordered }, dependent: :destroy

  accepts_nested_attributes_for :expense_items, allow_destroy: true, reject_if: :all_blank

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

  # Normalized expense details - always returns an array
  def normalized_expense_details
    normalize_details(expense_details)
  end

  # Normalized other revenue details - always returns an array
  def normalized_other_revenue_details
    normalize_details(other_revenue_details)
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
    details = other_revenue_details
    # Handle case where data is stored as hash (from form params) instead of array
    details = details.values if details.is_a?(Hash)

    if details.is_a?(Array) && details.any?
      details.sum do |item|
        if item.is_a?(Hash)
          item["amount"].to_f
        else
          0
        end
      end
    else
      other_revenue || 0
    end
  end

  # Calculate expenses from expense_items (preferred) or legacy expense_details
  def calculated_expenses
    # Prefer expense_items if present
    if expense_items.loaded? ? expense_items.any? : expense_items.exists?
      return expense_items.sum(:amount).to_f
    end

    # Fall back to legacy JSONB expense_details
    details = expense_details
    # Handle case where data is stored as hash (from form params) instead of array
    details = details.values if details.is_a?(Hash)

    if details.is_a?(Array) && details.any?
      details.sum do |item|
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

  # Calculate ticket fees from stored fees array
  def calculated_ticket_fees
    return 0 unless ticket_sales? && ticket_fees.is_a?(Array) && ticket_fees.any?

    ticket_fees.sum do |fee|
      fee["amount"].to_f
    end
  end

  # Recalculate ticket fees from templates
  def recalculate_ticket_fees!
    return unless ticket_sales?

    self.ticket_fees = ticket_fees.map do |fee|
      template = TicketFeeTemplate.find_by(id: fee["template_id"])
      if template
        template.to_fee_hash(ticket_count: ticket_count.to_i, ticket_revenue: ticket_revenue.to_f)
      else
        # Keep the fee but recalculate amount
        flat_total = (fee["flat"].to_f) * ticket_count.to_i
        pct_total = (fee["pct"].to_f) / 100.0 * ticket_revenue.to_f
        fee.merge("amount" => (flat_total + pct_total).round(2))
      end
    end
  end

  # Calculate production expense allocations for this show
  def calculated_production_expenses
    show.production_expense_allocations.sum(:allocated_amount).to_f
  end

  # Net revenue after expenses, ticket fees, and production expense allocations
  def net_revenue
    total_revenue - calculated_expenses - calculated_ticket_fees - calculated_production_expenses
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

  private

  # Normalize details data - converts hash to array if needed
  def normalize_details(details)
    return [] if details.blank?
    return details.values if details.is_a?(Hash)
    return details if details.is_a?(Array)
    []
  end
end

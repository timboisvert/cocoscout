# frozen_string_literal: true

# Calculates payouts for a show based on financial data and payout rules.
#
# Usage:
#   result = PayoutCalculator.calculate(show: show, rules: rules)
#   # => { success: true, total: 250.0, line_items: [...] }
#
#   preview = PayoutCalculator.preview(rules: rules, financials: { ticket_count: 50, ... }, performer_count: 4)
#   # => { success: true, total: 200.0, per_person: 50.0, breakdown: [...] }
#
class PayoutCalculator
  class << self
    # Calculate and persist payouts for a show
    def calculate(show:, rules:)
      new(show: show, rules: rules).calculate
    end

    # Preview calculation without persisting (for UI feedback)
    def preview(rules:, financials:, performer_count:)
      new(rules: rules, preview_financials: financials, preview_performer_count: performer_count).preview
    end
  end

  def initialize(show: nil, rules:, preview_financials: nil, preview_performer_count: nil)
    @show = show
    @rules = rules.deep_stringify_keys
    @preview_financials = preview_financials
    @preview_performer_count = preview_performer_count
  end

  # Calculate and persist payouts
  def calculate
    return { success: false, error: "No show provided" } unless @show
    return { success: false, error: "No rules provided" } unless @rules.present?

    financials = @show.show_financials
    return { success: false, error: "No financial data" } unless financials&.complete?

    # Get performers from show assignments
    assignments = @show.show_person_role_assignments.includes(:assignable, :role)
    performers = assignments.map(&:assignable).compact.uniq

    return { success: false, error: "No performers assigned to this show" } if performers.empty?

    # Build inputs
    inputs = {
      ticket_count: financials.ticket_count.to_i,
      ticket_revenue: financials.ticket_revenue.to_f,
      primary_revenue: financials.primary_revenue,
      other_revenue: financials.calculated_other_revenue,
      expenses: financials.calculated_expenses,
      total_revenue: financials.total_revenue,
      net_revenue: financials.net_revenue,
      performer_count: performers.count,
      revenue_type: financials.revenue_type
    }

    # Calculate performer pool and individual amounts
    result = calculate_payouts(inputs, performers)

    return { success: false, error: result[:error] } if result[:error]

    # Persist line items
    payout = @show.show_payout
    ActiveRecord::Base.transaction do
      # Clear existing line items
      payout.line_items.destroy_all

      # Create new line items
      result[:line_items].each do |item|
        payout.line_items.create!(
          payee: item[:payee],
          amount: item[:amount],
          shares: item[:shares],
          calculation_details: item[:calculation_details]
        )
      end

      payout.update!(
        calculated_at: Time.current,
        total_payout: result[:total]
      )
    end

    { success: true, total: result[:total], line_items: payout.line_items.reload }
  rescue => e
    Rails.logger.error "PayoutCalculator error: #{e.message}"
    { success: false, error: e.message }
  end

  # Preview calculation without persisting
  def preview
    return { success: false, error: "No rules provided" } unless @rules.present?
    return { success: false, error: "No financials provided" } unless @preview_financials.present?

    inputs = {
      ticket_count: @preview_financials[:ticket_count].to_i,
      ticket_revenue: @preview_financials[:ticket_revenue].to_f,
      other_revenue: @preview_financials[:other_revenue].to_f || 0,
      expenses: @preview_financials[:expenses].to_f || 0,
      total_revenue: (@preview_financials[:ticket_revenue].to_f) + (@preview_financials[:other_revenue].to_f || 0),
      net_revenue: (@preview_financials[:ticket_revenue].to_f) + (@preview_financials[:other_revenue].to_f || 0) - (@preview_financials[:expenses].to_f || 0),
      performer_count: @preview_performer_count.to_i
    }

    # For preview, create mock performers
    mock_performers = (1..inputs[:performer_count]).map { |i| OpenStruct.new(id: i, name: "Performer #{i}") }

    result = calculate_payouts(inputs, mock_performers)

    {
      success: true,
      total: result[:total],
      per_person: result[:per_person],
      performer_pool: result[:performer_pool],
      breakdown: result[:breakdown]
    }
  end

  private

  def calculate_payouts(inputs, performers)
    allocation = @rules["allocation"] || []
    distribution = @rules["distribution"] || {}
    method = distribution["method"] || "equal"
    overrides = @rules["performer_overrides"] || {}

    # Step 1: Calculate performer pool via allocation rules
    performer_pool = calculate_performer_pool(inputs, allocation)
    breakdown = [ "Starting revenue: #{format_currency(inputs[:total_revenue])}" ]

    if inputs[:expenses] > 0
      breakdown << "Expenses: -#{format_currency(inputs[:expenses])}"
    end

    # Step 2: Distribute to performers based on method
    line_items = case method
    when "equal"
      distribute_equal(performer_pool, performers, overrides, breakdown)
    when "shares"
      distribute_shares(performer_pool, performers, distribution, overrides, breakdown)
    when "per_ticket"
      distribute_per_ticket(inputs, performers, distribution, overrides, breakdown)
    when "per_ticket_guaranteed"
      distribute_per_ticket_guaranteed(inputs, performers, distribution, overrides, breakdown)
    when "flat_fee"
      distribute_flat_fee(performers, distribution, overrides, breakdown)
    else
      return { error: "Unknown distribution method: #{method}" }
    end

    total = line_items.sum { |li| li[:amount] }
    per_person = performers.any? ? (total / performers.count) : 0

    {
      total: total.round(2),
      per_person: per_person.round(2),
      performer_pool: performer_pool.round(2),
      line_items: line_items,
      breakdown: breakdown
    }
  end

  def calculate_performer_pool(inputs, allocation)
    remaining = inputs[:net_revenue]

    allocation.each do |step|
      case step["type"]
      when "flat"
        remaining -= step["amount"].to_f
      when "percentage"
        house_take = inputs[:total_revenue] * (step["value"].to_f / 100)
        remaining = inputs[:total_revenue] - house_take - inputs[:expenses]
      when "expenses_first"
        # Already handled in net_revenue
      when "remainder"
        # Pool is the remainder - already calculated
      end
    end

    [ remaining, 0 ].max
  end

  def distribute_equal(pool, performers, overrides, breakdown)
    return [] if performers.empty?

    per_person = pool / performers.count
    breakdown << "Performer pool: #{format_currency(pool)} ÷ #{performers.count} = #{format_currency(per_person)} each"

    performers.map do |performer|
      override = overrides[performer.id.to_s] || {}
      amount = override["flat_amount"] || per_person

      {
        payee: performer,
        amount: amount.round(2),
        shares: 1,
        calculation_details: {
          formula: "#{format_currency(pool)} ÷ #{performers.count} performers",
          inputs: { pool: pool, performer_count: performers.count },
          breakdown: [ "Equal split: #{format_currency(per_person)}" ]
        }
      }
    end
  end

  def distribute_shares(pool, performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    default_shares = distribution["default_shares"].to_f || 1.0

    # Calculate total shares
    total_shares = performers.sum do |performer|
      override = overrides[performer.id.to_s] || {}
      override["shares"]&.to_f || default_shares
    end

    breakdown << "Performer pool: #{format_currency(pool)}, Total shares: #{total_shares}"

    per_share = total_shares > 0 ? pool / total_shares : 0

    performers.map do |performer|
      override = overrides[performer.id.to_s] || {}
      shares = override["shares"]&.to_f || default_shares
      amount = per_share * shares

      {
        payee: performer,
        amount: amount.round(2),
        shares: shares,
        calculation_details: {
          formula: "#{format_currency(pool)} × (#{shares} ÷ #{total_shares} shares)",
          inputs: { pool: pool, shares: shares, total_shares: total_shares },
          breakdown: [ "#{shares} shares × #{format_currency(per_share)}/share = #{format_currency(amount)}" ]
        }
      }
    end
  end

  def distribute_per_ticket(inputs, performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    rate = distribution["per_ticket_rate"].to_f || 1.0
    ticket_count = inputs[:ticket_count]
    per_person = rate * ticket_count

    breakdown << "#{ticket_count} tickets × #{format_currency(rate)}/ticket = #{format_currency(per_person)} per performer"

    performers.map do |performer|
      override = overrides[performer.id.to_s] || {}
      custom_rate = override["per_ticket_rate"]&.to_f || rate
      amount = custom_rate * ticket_count

      {
        payee: performer,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: "#{ticket_count} tickets × #{format_currency(custom_rate)}",
          inputs: { ticket_count: ticket_count, rate: custom_rate },
          breakdown: [ "#{ticket_count} × #{format_currency(custom_rate)} = #{format_currency(amount)}" ]
        }
      }
    end
  end

  def distribute_per_ticket_guaranteed(inputs, performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    rate = distribution["per_ticket_rate"].to_f || 1.0
    minimum = distribution["minimum"].to_f || 0
    ticket_count = inputs[:ticket_count]
    calculated = rate * ticket_count
    per_person = [ calculated, minimum ].max

    breakdown << "#{ticket_count} tickets × #{format_currency(rate)} = #{format_currency(calculated)}, min #{format_currency(minimum)} → #{format_currency(per_person)} per performer"

    performers.map do |performer|
      override = overrides[performer.id.to_s] || {}
      custom_rate = override["per_ticket_rate"]&.to_f || rate
      custom_min = override["minimum"]&.to_f || minimum
      calculated_amount = custom_rate * ticket_count
      amount = [ calculated_amount, custom_min ].max

      {
        payee: performer,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: "max(#{ticket_count} × #{format_currency(custom_rate)}, #{format_currency(custom_min)})",
          inputs: { ticket_count: ticket_count, rate: custom_rate, minimum: custom_min },
          breakdown: [
            "Calculated: #{format_currency(calculated_amount)}",
            "Minimum: #{format_currency(custom_min)}",
            "Paid: #{format_currency(amount)}"
          ]
        }
      }
    end
  end

  def distribute_flat_fee(performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    flat_amount = distribution["flat_amount"].to_f || 0
    breakdown << "Flat fee: #{format_currency(flat_amount)} per performer"

    performers.map do |performer|
      override = overrides[performer.id.to_s] || {}
      amount = override["flat_amount"]&.to_f || flat_amount

      {
        payee: performer,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: "Flat fee",
          inputs: { flat_amount: amount },
          breakdown: [ "Fixed: #{format_currency(amount)}" ]
        }
      }
    end
  end

  def format_currency(amount)
    "$#{'%.2f' % amount}"
  end
end

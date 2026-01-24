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

    # Get performers from show assignments (including guests)
    assignments = @show.show_person_role_assignments.includes(:assignable, :role)
    
    # Separate regular performers and guest assignments
    regular_performers = assignments.reject(&:guest?).map(&:assignable).compact.uniq
    guest_assignments = assignments.select(&:guest?)

    total_performer_count = regular_performers.count + guest_assignments.count

    return { success: false, error: "No performers assigned to this show" } if total_performer_count == 0

    # Build inputs
    inputs = {
      ticket_count: financials.ticket_count.to_i,
      ticket_revenue: financials.ticket_revenue.to_f,
      primary_revenue: financials.primary_revenue,
      other_revenue: financials.calculated_other_revenue,
      expenses: financials.calculated_expenses,
      total_revenue: financials.total_revenue,
      net_revenue: financials.net_revenue,
      performer_count: total_performer_count,
      revenue_type: financials.revenue_type
    }

    # Get distribution method and overrides
    distribution = @rules["distribution"] || {}
    method = distribution["method"] || "equal"
    overrides = @rules["performer_overrides"] || {}

    # Calculate performer pool and individual amounts for regular performers
    result = calculate_payouts(inputs, regular_performers)

    return { success: false, error: result[:error] } if result[:error]

    # Determine per-person amount and whether to adjust line items
    # For pool-based methods (equal, shares, per_ticket, per_ticket_guaranteed), divide pool by total performers
    # For flat_fee, use the flat_amount directly
    # For no_pay, everyone gets $0
    case method
    when "flat_fee"
      # Flat fee: each person gets the flat amount (or their override)
      flat_amount = distribution["flat_amount"].to_f || 0
      per_person_amount = flat_amount
      
      # Don't adjust regular performer line items - they already have correct amounts from distribute_flat_fee
      adjusted_line_items = result[:line_items]
      
      # Calculate guest payouts with flat fee
      guest_line_items = calculate_guest_payouts_flat_fee(
        guest_assignments, 
        flat_amount, 
        overrides
      )
    when "no_pay"
      # No pay: everyone gets $0
      per_person_amount = 0
      adjusted_line_items = result[:line_items]
      guest_line_items = guest_assignments.map do |assignment|
        {
          guest_name: assignment.guest_name,
          guest_assignment_id: assignment.id,
          amount: 0,
          shares: nil,
          calculation_details: {
            formula: "No pay (non-revenue event)",
            inputs: {},
            breakdown: [ "Non-revenue: $0.00" ]
          }
        }
      end
    else
      # Pool-based methods: divide pool by total performers (including guests)
      per_person_amount = if total_performer_count > 0 && result[:performer_pool]
        (result[:performer_pool] / total_performer_count).round(2)
      else
        result[:per_person] || 0
      end

      # Adjust regular performer line items if there are guests
      # (they need to share the pool with guests)
      adjusted_line_items = if guest_assignments.any? && regular_performers.any?
        result[:line_items].map do |item|
          calc_details = item[:calculation_details] || {}
          existing_inputs = calc_details[:inputs] || calc_details["inputs"] || {}
          item.merge(
            amount: per_person_amount,
            calculation_details: {
              formula: "#{format_currency(result[:performer_pool])} ÷ #{total_performer_count} performers (including #{guest_assignments.count} guests)",
              inputs: existing_inputs.merge(total_performer_count: total_performer_count),
              breakdown: calc_details[:breakdown] || calc_details["breakdown"] || []
            }
          )
        end
      else
        result[:line_items]
      end

      # Calculate guest payouts using the same per-person amount (with overrides)
      guest_line_items = calculate_guest_payouts(
        guest_assignments, 
        inputs, 
        per_person_amount, 
        overrides,
        result[:performer_pool],
        total_performer_count
      )
    end

    # Persist line items
    payout = @show.show_payout
    ActiveRecord::Base.transaction do
      # Preserve existing guest payment info before destroying line items
      existing_guest_payment_info = {}
      payout.line_items.where(is_guest: true).each do |li|
        existing_guest_payment_info[li.guest_name] = {
          venmo: li.guest_venmo,
          zelle: li.guest_zelle
        }
      end

      # Clear existing line items
      payout.line_items.destroy_all

      # Create line items for regular performers
      adjusted_line_items.each do |item|
        payout.line_items.create!(
          payee: item[:payee],
          amount: item[:amount],
          shares: item[:shares],
          calculation_details: item[:calculation_details]
        )
      end

      # Create line items for guests (restoring payment info if it existed)
      guest_line_items.each do |item|
        existing_info = existing_guest_payment_info[item[:guest_name]] || {}
        payout.line_items.create!(
          is_guest: true,
          guest_name: item[:guest_name],
          guest_venmo: existing_info[:venmo],
          guest_zelle: existing_info[:zelle],
          amount: item[:amount],
          shares: item[:shares],
          calculation_details: item[:calculation_details]
        )
      end

      total = adjusted_line_items.sum { |i| i[:amount] } + guest_line_items.sum { |i| i[:amount] }
      payout.update!(
        calculated_at: Time.current,
        total_payout: total
      )
    end

    total = adjusted_line_items.sum { |i| i[:amount] } + guest_line_items.sum { |i| i[:amount] }
    { success: true, total: total, line_items: payout.line_items.reload }
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
    when "no_pay"
      distribute_no_pay(performers, breakdown)
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

  def distribute_no_pay(performers, breakdown)
    breakdown << "No pay: Non-revenue event"

    performers.map do |performer|
      {
        payee: performer,
        amount: 0,
        shares: nil,
        calculation_details: {
          formula: "No pay",
          inputs: {},
          breakdown: [ "Non-paying event" ]
        }
      }
    end
  end

  # Calculate payouts for guest performers using flat fee method
  def calculate_guest_payouts_flat_fee(guest_assignments, flat_amount, overrides = {})
    return [] if guest_assignments.empty?

    guest_assignments.map do |assignment|
      # Check for guest-specific override (keyed as "guest_#{assignment.id}")
      override = overrides["guest_#{assignment.id}"] || {}
      amount = override["flat_amount"]&.to_f || flat_amount

      formula = if override["flat_amount"].present?
        "Custom flat fee"
      else
        "Flat fee"
      end

      {
        guest_name: assignment.guest_name,
        guest_assignment_id: assignment.id,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: formula,
          inputs: { flat_amount: amount },
          breakdown: [ "Fixed: #{format_currency(amount)}" ]
        }
      }
    end
  end

  # Calculate payouts for guest performers (those without CocoScout accounts)
  def calculate_guest_payouts(guest_assignments, inputs, per_person_amount, overrides = {}, performer_pool = nil, total_performer_count = nil)
    return [] if guest_assignments.empty?

    per_person = per_person_amount || 0
    pool = performer_pool || inputs[:net_revenue]
    count = total_performer_count || inputs[:performer_count]
    guest_count = guest_assignments.count

    guest_assignments.map do |assignment|
      # Check for guest-specific override (keyed as "guest_#{assignment.id}")
      override = overrides["guest_#{assignment.id}"] || {}
      amount = override["flat_amount"]&.to_f || per_person

      formula = if override["flat_amount"].present?
        "Custom amount"
      elsif guest_count > 0
        "#{format_currency(pool)} ÷ #{count} performers (including #{guest_count} #{'guest'.pluralize(guest_count)})"
      else
        "#{format_currency(pool)} ÷ #{count} performers"
      end

      {
        guest_name: assignment.guest_name,
        guest_assignment_id: assignment.id,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: formula,
          inputs: { performer_pool: pool, performer_count: count },
          breakdown: [ "Guest performer: #{format_currency(amount)}" ]
        }
      }
    end
  end

  def format_currency(amount)
    "$#{'%.2f' % amount}"
  end
end

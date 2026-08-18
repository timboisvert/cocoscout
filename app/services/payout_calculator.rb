# frozen_string_literal: true

# Calculates payouts for a show based on financial data and payout rules.
#
# Usage:
#   result = PayoutCalculator.calculate(show: show, rules: rules)
#   # => { success: true, total: 250.0, line_items: [ShowPayoutLineItem, ...] }
#
#   dry_run = PayoutCalculator.calculate(show: show, rules: rules, persist: false)
#   # => { success: true, total: 250.0, line_items: [{ payee:, amount:, ... }, ...] }
#
#   preview = PayoutCalculator.preview(rules: rules, financials: { ticket_count: 50, ... }, performer_count: 4)
#   # => { success: true, total: 200.0, per_person: 50.0, breakdown: [...] }
#
# performer_overrides are keyed like ShowPayout.act_key: "Person_12" /
# "Group_3" for cast, "guest_45" for a guest slot. A bare "12" (written by
# older customizations) still finds Person 12 — and only a Person.
class PayoutCalculator
  class << self
    # Calculate payouts for a show and, unless persist: false, rebuild its
    # line items from them. act_counts is only used by act-based schemes:
    # { "Person_12" => 2, "guest_9" => 1 }. role_names — the show roles each
    # payee holds, { "Person_12" => ["MC"] } — is read off the show's cast
    # unless given.
    def calculate(show:, rules:, act_counts: {}, role_names: nil, persist: true)
      new(show: show, rules: rules, act_counts: act_counts, role_names: role_names, persist: persist).calculate
    end

    # Preview calculation without persisting (for UI feedback)
    def preview(rules:, financials:, performer_count:)
      new(rules: rules, preview_financials: financials, preview_performer_count: performer_count).preview
    end
  end

  def initialize(show: nil, rules:, preview_financials: nil, preview_performer_count: nil, act_counts: {}, role_names: nil, persist: true)
    @show = show
    @rules = rules&.deep_stringify_keys || {}
    @preview_financials = preview_financials
    @preview_performer_count = preview_performer_count
    @act_counts = (act_counts || {}).stringify_keys
    @role_names = role_names&.stringify_keys
    @persist = persist
    @guest_assignments = []
  end

  # Work out every payee's amount and, unless this is a dry run, persist them
  # as the show payout's line items. A dry run returns the same numbers as
  # plain hashes and touches nothing — no line items, no ledger, no
  # calculated_at.
  def calculate
    return { success: false, error: "No show provided" } unless @show
    return { success: false, error: "No rules provided" } unless @rules.present?

    financials = @show.show_financials
    # Act pay never reads revenue, so it can run before anyone enters ticket
    # numbers; every other method needs the night's financials.
    unless per_act_rules? || financials&.complete?
      return { success: false, error: "No financial data" }
    end

    # Get performers from show assignments (including guests). One entry per
    # payee — a guest in several acts is folded into one (see Show#pay_cast_assignments).
    cast = @show.pay_cast_assignments
    regular_performers = cast[:people]
    guest_assignments = cast[:guests]
    # The pool methods share the night's money with the guests too, so the
    # distribution step needs to know they're there.
    @guest_assignments = guest_assignments

    total_performer_count = regular_performers.count + guest_assignments.count

    return { success: false, error: "No performers assigned to this show" } if total_performer_count == 0

    # Build inputs
    inputs = if financials&.complete?
      {
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
    else
      {
        ticket_count: 0, ticket_revenue: 0.0, primary_revenue: 0.0, other_revenue: 0.0,
        expenses: 0.0, total_revenue: 0.0, net_revenue: 0.0,
        performer_count: total_performer_count, revenue_type: nil
      }
    end

    # Get distribution method and overrides
    distribution = @rules["distribution"] || {}
    method = distribution["method"] || "equal"
    overrides = @rules["performer_overrides"] || {}

    # Calculate performer pool and individual amounts for regular performers
    result = calculate_payouts(inputs, regular_performers)

    return { success: false, error: result[:error] } if result[:error]

    # Extract individual allocation items (e.g., producer percentages)
    individual_allocation_items = result[:individual_allocation_items] || []

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
    when "per_act"
      # Act-based: everyone's amount comes from their own act count, so there's
      # no pool to share and nothing to adjust for guests.
      per_person_amount = 0
      adjusted_line_items = result[:line_items]
      guest_line_items = calculate_guest_payouts_per_act(guest_assignments, distribution, overrides)
    when "per_ticket", "per_ticket_guaranteed"
      # Per-ticket pay is rate × tickets for each person — nothing is shared,
      # so guests are worked out the same way and nobody's line is re-split.
      per_person_amount = 0
      adjusted_line_items = result[:line_items]
      guest_line_items = calculate_guest_payouts_per_ticket(guest_assignments, inputs, distribution, overrides)
    when "no_pay"
      # No pay: everyone gets $0 — unless tonight's customization names an
      # exact amount for someone.
      per_person_amount = 0
      adjusted_line_items = result[:line_items]
      guest_line_items = guest_assignments.map do |assignment|
        override = override_for(overrides, assignment)
        if override["flat_amount"].present?
          custom_amount_item(override["flat_amount"]).merge(guest_name: assignment.guest_name, guest_assignment_id: assignment.id)
        else
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
      end
    when "shares"
      # Shares: distribute_shares already counted the guests into the total
      # (default_shares each), so the cast lines stand; the guests are paid
      # their shares of the same pool.
      per_person_amount = 0
      adjusted_line_items = result[:line_items]
      guest_line_items = calculate_guest_payouts_shares(guest_assignments, distribution, overrides, result[:performer_pool], regular_performers)
    else
      # Equal split: the pool is divided per head, guests included.
      per_person_amount = if total_performer_count > 0 && result[:performer_pool]
        (result[:performer_pool] / total_performer_count).round(2)
      else
        result[:per_person] || 0
      end

      # Adjust regular performer line items if there are guests
      # (they need to share the pool with guests). A person given an exact
      # amount for tonight keeps it — the re-split is for everyone else.
      adjusted_line_items = if guest_assignments.any? && regular_performers.any?
        result[:line_items].map do |item|
          next item if custom_amount_for(overrides, item[:payee]).present?

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

    # Every line as a hash, the way a line item will be built from it: cast
    # lines, guest lines (flagged, keyed by the guest slot) and anyone's cut
    # off the top (flagged as an individual allocation).
    line_item_hashes =
      adjusted_line_items +
      guest_line_items.map { |item| item.merge(is_guest: true) } +
      individual_allocation_items.map { |item| item.merge(is_individual_allocation: true) }
    total = line_item_hashes.sum { |i| i[:amount] }

    return { success: true, total: total, line_items: line_item_hashes } unless @persist

    # Persist line items
    payout = @show.show_payout
    ActiveRecord::Base.transaction do
      # Clear existing line items (also clears advance recoveries via dependent: :destroy)
      payout.line_items.destroy_all

      line_item_hashes.each do |item|
        # A guest has no record of their own; the slot they were paid for
        # rides along in the details so the line can be matched back to it.
        details = item[:calculation_details] || {}
        details = details.merge(guest_assignment_id: item[:guest_assignment_id]) if item[:is_guest]

        payout.line_items.create!(
          payee: item[:payee],
          is_guest: item[:is_guest] || false,
          guest_name: item[:guest_name],
          amount: item[:amount],
          shares: item[:shares],
          calculation_details: details,
          is_individual_allocation: item[:is_individual_allocation] || false
        )
        # Advances are no longer deducted at calc time — earnings post gross and
        # advances net against them on the payout ledger (see AdvancePayoutService).
      end

      payout.update!(
        calculated_at: Time.current,
        total_payout: total
      )

      # Mirror the calculated line items onto the company-wide payout ledger.
      payout.sync_earnings_to_ledger!
    end

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

    # Step 1: Calculate performer pool and individual allocations via allocation rules
    allocation_result = calculate_performer_pool_and_individual_allocations(inputs, allocation)
    performer_pool = allocation_result[:performer_pool]
    individual_allocation_items = allocation_result[:individual_allocation_items]
    breakdown = [ "Starting revenue: #{format_currency(inputs[:total_revenue])}" ]

    if inputs[:expenses] > 0
      breakdown << "Expenses: -#{format_currency(inputs[:expenses])}"
    end

    # Add individual allocation breakdowns
    individual_allocation_items.each do |item|
      breakdown << "#{item[:label]}: #{format_currency(item[:amount])}"
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
    when "per_act"
      distribute_per_act(performers, distribution, overrides, breakdown)
    when "no_pay"
      distribute_no_pay(performers, overrides, breakdown)
    else
      return { error: "Unknown distribution method: #{method}" }
    end

    total = line_items.sum { |li| li[:amount] } + individual_allocation_items.sum { |li| li[:amount] }
    per_person = performers.any? ? (line_items.sum { |li| li[:amount] } / performers.count) : 0

    {
      total: total.round(2),
      per_person: per_person.round(2),
      performer_pool: performer_pool.round(2),
      line_items: line_items,
      individual_allocation_items: individual_allocation_items,
      breakdown: breakdown
    }
  end

  def calculate_performer_pool_and_individual_allocations(inputs, allocation)
    remaining = inputs[:net_revenue]
    individual_allocation_items = []

    allocation.each do |step|
      case step["type"]
      when "flat"
        remaining -= step["amount"].to_f
      when "percentage"
        amount = inputs[:total_revenue] * (step["value"].to_f / 100)
        # Check if this goes to a specific person (individual allocation)
        if step["person_id"].present?
          person = Person.find_by(id: step["person_id"])
          if person
            individual_allocation_items << {
              payee: person,
              amount: amount.round(2),
              shares: nil,
              label: step["label"] || "#{person.name} (#{step['value']}%)",
              calculation_details: {
                formula: "#{step['value']}% of revenue",
                inputs: { total_revenue: inputs[:total_revenue], percentage: step["value"] },
                breakdown: [ "#{step['value']}% × #{format_currency(inputs[:total_revenue])} = #{format_currency(amount)}" ]
              }
            }
          end
          remaining -= amount
        else
          # House take - deduct from remaining
          remaining = inputs[:total_revenue] - amount - inputs[:expenses]
        end
      when "expenses_first"
        # Already handled in net_revenue
      when "remainder"
        # Pool is the remainder - already calculated
      end
    end

    { performer_pool: [ remaining, 0 ].max, individual_allocation_items: individual_allocation_items }
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
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer, shares: 1) if custom

      {
        payee: performer,
        amount: per_person.round(2),
        shares: 1,
        calculation_details: {
          formula: "#{format_currency(pool)} ÷ #{performers.count} performers",
          inputs: { pool: pool, performer_count: performers.count },
          breakdown: [ "Equal split: #{format_currency(per_person)}" ]
        }
      }
    end
  end

  # Shares: the pool is split by everyone's shares — the cast's (their own
  # override or default_shares each) and any guests' (default_shares each, or
  # their slot's override). Guests are paid their part in
  # calculate_guest_payouts_shares from the same split.
  def distribute_shares(pool, performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    split = shares_split(pool, performers, distribution, overrides)
    total_shares = split[:total_shares]
    per_share = split[:per_share]

    guest_count = @guest_assignments.count
    breakdown << if guest_count.positive?
      "Performer pool: #{format_currency(pool)}, Total shares: #{total_shares} (including #{guest_count} #{'guest'.pluralize(guest_count)})"
    else
      "Performer pool: #{format_currency(pool)}, Total shares: #{total_shares}"
    end

    performers.map do |performer|
      shares = shares_for(overrides, performer, distribution)
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer, shares: shares) if custom

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
      override = override_for(overrides, performer)
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer) if custom

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
      override = override_for(overrides, performer)
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer) if custom

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
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer) if custom

      {
        payee: performer,
        amount: flat_amount.round(2),
        shares: nil,
        calculation_details: {
          formula: "Flat fee",
          inputs: { flat_amount: flat_amount },
          breakdown: [ "Fixed: #{format_currency(flat_amount)}" ]
        }
      }
    end
  end

  # Act-based: each performer is paid off their own act count for this show,
  # which the manager entered when they kicked off the calculation.
  def distribute_per_act(performers, distribution, overrides, breakdown)
    return [] if performers.empty?

    breakdown << "Paid by acts: #{act_rules_label(distribution)}"

    performers.map do |performer|
      key = ShowPayout.act_key(performer)
      acts = act_count_for(key)
      roles = role_names_for(key)
      override = override_for(overrides, performer)
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom, inputs: per_act_inputs(acts, roles)).merge(payee: performer) if custom

      per_act_line(distribution, override, acts, roles).merge(payee: performer)
    end
  end

  # Guests are paid by acts too — their counts are keyed by assignment.
  def calculate_guest_payouts_per_act(guest_assignments, distribution, overrides = {})
    return [] if guest_assignments.empty?

    guest_assignments.map do |assignment|
      key = ShowPayout.act_key(assignment)
      acts = act_count_for(key)
      roles = role_names_for(key)
      override = override_for(overrides, assignment)
      if override["flat_amount"].present?
        next custom_amount_item(override["flat_amount"], inputs: per_act_inputs(acts, roles))
               .merge(guest_name: assignment.guest_name, guest_assignment_id: assignment.id)
      end

      per_act_line(distribution, override, acts, roles)
        .merge(guest_name: assignment.guest_name, guest_assignment_id: assignment.id)
    end
  end

  # One payee's act-based line: act pay off their count, plus whatever show
  # roles they hold (MC, Stage Kitten) priced by name, combined the way the
  # calculation's role_stacking says. A payee holding no show roles reads
  # exactly as before — act pay alone.
  def per_act_line(distribution, override, acts, role_names)
    act_amount, act_formula = per_act_amount_and_formula(distribution, override, acts)
    acts_label = "#{acts} #{'act'.pluralize(acts)}"
    act_line = "#{acts_label} = #{format_currency(act_amount)}"

    priced = role_names.filter_map do |name|
      amount = PayoutScheme.role_amount_for(distribution, name)
      [ name, amount ] if amount
    end
    unpriced = role_names - priced.map(&:first)

    if priced.empty?
      breakdown = [ act_rules_label(distribution), act_line ]
      breakdown.concat(unpriced.map { |name| "#{name}: not priced in this calculation" })
      return {
        amount: act_amount,
        shares: nil,
        calculation_details: {
          formula: act_formula,
          inputs: per_act_inputs(acts, role_names),
          breakdown: breakdown
        }
      }
    end

    role_amount = priced.sum { |_, amount| amount }.round(2)
    role_label = priced.map(&:first).to_sentence
    stacking = PayoutScheme.role_stacking(distribution)

    amount, formula = case stacking
    when "role_only"
      [ role_amount, acts.positive? ? "#{role_label} (role only; #{acts_label} not paid on top)" : role_label ]
    when "higher"
      if acts.zero?
        [ role_amount, role_label ]
      elsif role_amount >= act_amount
        [ role_amount, "#{role_label} (higher than #{acts_label})" ]
      else
        [ act_amount, "#{act_formula} (higher than #{role_label})" ]
      end
    else
      [ (role_amount + act_amount).round(2), acts.positive? ? "#{role_label} + #{act_formula}" : role_label ]
    end

    breakdown = [ act_rules_label(distribution) ]
    breakdown << "Show roles: #{priced.map { |name, a| "#{name} #{format_currency(a)}" }.join(', ')}"
    breakdown << act_line
    breakdown.concat(unpriced.map { |name| "#{name}: not priced in this calculation" })
    breakdown << "Show role pay #{PayoutScheme.role_stacking_phrase(stacking)}: #{format_currency(amount)}"

    {
      amount: amount,
      shares: nil,
      calculation_details: {
        formula: formula,
        inputs: per_act_inputs(acts, role_names).merge(role_pay: role_amount, act_pay: act_amount, stacking: stacking),
        breakdown: breakdown
      }
    }
  end

  # { acts: } as always; the roles ride along only when the payee holds one,
  # so a plain act-only line item looks exactly as it did.
  def per_act_inputs(acts, role_names)
    inputs = { acts: acts }
    inputs[:roles] = role_names if role_names.any?
    inputs
  end

  # A flat per-act override beats the scheme's own rate/tiers for that person.
  def per_act_amount_and_formula(distribution, override, acts)
    if override["per_act_rate"].present?
      rate = override["per_act_rate"].to_f
      [ (rate * acts).round(2), "#{acts} #{'act'.pluralize(acts)} × #{format_currency(rate)}/act (custom rate)" ]
    else
      [ PayoutScheme.act_amount(distribution, acts), "#{acts} #{'act'.pluralize(acts)}" ]
    end
  end

  def per_act_rules?
    @rules.dig("distribution", "method").to_s == "per_act"
  end

  def act_count_for(key)
    @act_counts[key].to_i
  end

  # The show roles this payee holds tonight — given to the calculator, or read
  # off the show's cast. A preview with no show has none.
  def role_names_for(key)
    @role_names ||= (@show&.show_role_names_by_payee || {}).to_h.stringify_keys
    Array(@role_names.fetch(key, []))
  end

  def act_rules_label(distribution)
    PayoutScheme.act_rules_description(distribution)
  end

  def distribute_no_pay(performers, overrides, breakdown)
    breakdown << "No pay: Non-revenue event"

    performers.map do |performer|
      custom = custom_amount_for(overrides, performer)
      next custom_amount_item(custom).merge(payee: performer) if custom

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
      override = override_for(overrides, assignment)
      amount = override["flat_amount"]&.to_f || flat_amount

      formula = if override["flat_amount"].present?
        "Custom amount"
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
      override = override_for(overrides, assignment)
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

  # Guests on a per-ticket night: rate × tickets, honouring the minimum on the
  # guaranteed variant and any per-guest rate/minimum/flat override.
  def calculate_guest_payouts_per_ticket(guest_assignments, inputs, distribution, overrides = {})
    return [] if guest_assignments.empty?

    guaranteed = distribution["method"] == "per_ticket_guaranteed"
    ticket_count = inputs[:ticket_count]

    guest_assignments.map do |assignment|
      override = override_for(overrides, assignment)
      rate = override["per_ticket_rate"]&.to_f || distribution["per_ticket_rate"].to_f
      minimum = guaranteed ? (override["minimum"]&.to_f || distribution["minimum"].to_f) : 0
      amount = if override["flat_amount"].present?
        override["flat_amount"].to_f
      else
        [ rate * ticket_count, minimum ].max
      end

      formula = if override["flat_amount"].present?
        "Custom amount"
      elsif guaranteed && rate * ticket_count < minimum
        "Minimum #{format_currency(minimum)} (#{ticket_count} × #{format_currency(rate)} = #{format_currency(rate * ticket_count)})"
      else
        "#{ticket_count} tickets × #{format_currency(rate)}"
      end

      {
        guest_name: assignment.guest_name,
        guest_assignment_id: assignment.id,
        amount: amount.round(2),
        shares: nil,
        calculation_details: {
          formula: formula,
          inputs: { ticket_count: ticket_count, rate: rate, minimum: minimum },
          breakdown: [ "Guest performer: #{format_currency(amount)}" ]
        }
      }
    end
  end

  # (Advances are no longer deducted at calc time — they net on the payout ledger
  # via AdvancePayoutService. The old apply_advance_deductions was removed.)

  # Guests on a shares night: their shares of the same split the cast was paid
  # from (see shares_split), or an exact amount set for their slot.
  def calculate_guest_payouts_shares(guest_assignments, distribution, overrides, pool, performers)
    return [] if guest_assignments.empty?

    split = shares_split(pool.to_f, performers, distribution, overrides)
    total_shares = split[:total_shares]
    per_share = split[:per_share]

    guest_assignments.map do |assignment|
      shares = shares_for(overrides, assignment, distribution)
      override = override_for(overrides, assignment)
      if override["flat_amount"].present?
        next custom_amount_item(override["flat_amount"]).merge(guest_name: assignment.guest_name, guest_assignment_id: assignment.id, shares: shares)
      end

      amount = per_share * shares
      {
        guest_name: assignment.guest_name,
        guest_assignment_id: assignment.id,
        amount: amount.round(2),
        shares: shares,
        calculation_details: {
          formula: "#{format_currency(pool)} × (#{shares} ÷ #{total_shares} shares)",
          inputs: { pool: pool, shares: shares, total_shares: total_shares },
          breakdown: [ "Guest performer: #{shares} shares × #{format_currency(per_share)}/share = #{format_currency(amount)}" ]
        }
      }
    end
  end

  # The shares split of a pool between the cast and the guests on the show:
  # everyone's shares added up, and what one share is worth.
  def shares_split(pool, performers, distribution, overrides)
    total_shares = (performers + @guest_assignments).sum { |payee| shares_for(overrides, payee, distribution) }
    per_share = total_shares > 0 ? pool / total_shares : 0
    { total_shares: total_shares, per_share: per_share }
  end

  # How many shares a payee holds: their override's, else the calculation's
  # default_shares (guests included).
  def shares_for(overrides, payee, distribution)
    default_shares = distribution["default_shares"].to_f || 1.0
    override_for(overrides, payee)["shares"]&.to_f || default_shares
  end

  # A payee's entry in performer_overrides, keyed like ShowPayout.act_key
  # ("Person_12", "Group_3", "guest_45"). Older customizations wrote a bare
  # person id ("12"); that still finds a Person — never a Group, so Person 7
  # and Group 7 can't be mixed up. {} when they have none.
  def override_for(overrides, payee)
    return {} if payee.nil? || overrides.blank?

    override = overrides[ShowPayout.act_key(payee)]
    override = overrides[payee.id.to_s] if override.nil? && payee.is_a?(Person)
    override || {}
  end

  # An exact amount set for one payee tonight (performer_overrides[act_key]
  # ["flat_amount"]) beats whatever the method would have worked out for them,
  # whichever method that is. nil when they're paid as calculated.
  def custom_amount_for(overrides, payee)
    value = override_for(overrides, payee)["flat_amount"]
    value.present? ? value.to_f : nil
  end

  def custom_amount_item(amount, inputs: {})
    amount = amount.to_f.round(2)
    {
      amount: amount,
      shares: nil,
      calculation_details: {
        formula: "Custom amount",
        inputs: inputs.merge(flat_amount: amount, custom: true),
        breakdown: [ "Set for this show: #{format_currency(amount)}" ]
      }
    }
  end

  def format_currency(amount)
    "$#{'%.2f' % amount}"
  end
end

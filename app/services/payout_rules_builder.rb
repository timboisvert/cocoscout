# frozen_string_literal: true

# Turns what a manager typed into the rules jsonb a payout calculation runs on.
#
# One place for the shape, whether the numbers came from the calculation
# wizard (a whole calculation), or from a show's Customize modal (tonight's
# amounts laid over the calculation the show inherited).
#
#   PayoutRulesBuilder.build(params)                    # => full rules hash
#   PayoutRulesBuilder.override(base_rules, params)     # => base with this event's edits on top
#   PayoutRulesBuilder.same_amount(base_rules, amount)  # => base, but everyone gets one flat amount
#
# Rules shape (unchanged from before — PayoutCalculator reads it):
#   { "allocation" => [ {type: expenses_first} | {type: percentage, value:, label:} |
#                       {type: percentage, value:, person_id:, label:} | {type: remainder} ],
#     "distribution" => { "method" => …, per-method keys
#                         (per_act may also carry "role_amounts" => [{name:, amount:}] and
#                          "role_stacking" => both|role_only|higher — see PayoutScheme) },
#     "performer_overrides" => { "Person_<id>" | "Group_<id>" | "guest_<assignment_id>" => { flat_amount:, … } } }
#   (performer_overrides are keyed like ShowPayout.act_key; older rules keyed a
#   person by bare id, which PayoutCalculator still reads — for a Person only.)
class PayoutRulesBuilder
  METHODS = %w[no_pay flat_fee per_act per_ticket per_ticket_guaranteed equal shares].freeze
  # Only these split a pool of the night's money, so only they have a
  # "before performers are paid" (house / expenses / someone's cut) step.
  POOL_METHODS = %w[equal shares].freeze

  class << self
    def build(params)
      p = normalize(params)
      method = p[:method].to_s
      method = "equal" unless METHODS.include?(method)

      {
        "allocation" => build_allocation(method, p),
        "distribution" => build_distribution(method, p),
        "performer_overrides" => build_performer_overrides(p[:performer_overrides])
      }
    end

    # Tonight's changes on top of the calculation the show already has. The
    # method never changes here (a different approach = choose a different
    # calculation); amounts, house/expenses (pool methods only) and exact
    # per-person amounts do. Keys the modal didn't send are kept from the base.
    def override(base_rules, params)
      base = (base_rules || {}).deep_dup.deep_stringify_keys
      p = normalize(params)
      method = base.dig("distribution", "method").to_s
      method = "equal" unless METHODS.include?(method)

      distribution = if p[:distribution].present?
        build_distribution(method, p)
      else
        (base["distribution"] || {}).merge("method" => method)
      end

      allocation = if POOL_METHODS.include?(method) && p.key?(:house_percentage)
        build_allocation(method, p)
      else
        base["allocation"] || []
      end

      overrides = if p.key?(:performer_overrides)
        build_performer_overrides(p[:performer_overrides])
      else
        base["performer_overrides"] || {}
      end

      { "allocation" => allocation, "distribution" => distribution, "performer_overrides" => overrides }
    end

    # "Pay everyone the same amount" for one event: the calculation's rules with
    # the distribution swapped for a flat amount each — no cut off the top, no
    # per-person exceptions.
    def same_amount(base_rules, amount)
      base = (base_rules || {}).deep_dup.deep_stringify_keys
      base.merge(
        "allocation" => [],
        "distribution" => { "method" => "flat_fee", "flat_amount" => amount.to_f },
        "performer_overrides" => {}
      )
    end

    def pool_method?(method)
      POOL_METHODS.include?(method.to_s)
    end

    private

    def normalize(params)
      hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      hash.deep_symbolize_keys
    end

    def build_allocation(method, p)
      return [] unless pool_method?(method)

      allocation = []
      allocation << { "type" => "expenses_first" } if truthy?(p[:expenses_first])

      house = p[:house_percentage].to_f
      allocation << { "type" => "percentage", "value" => house, "label" => "House take" } if house.positive?

      each_row(p[:individual_allocations]) do |row|
        next if row[:person_id].blank? || row[:percentage].blank?

        allocation << {
          "type" => "percentage",
          "value" => row[:percentage].to_f,
          "person_id" => row[:person_id].to_i,
          "label" => row[:label].presence
        }
      end

      allocation << { "type" => "remainder", "label" => "Performer pool" }
      allocation
    end

    def build_distribution(method, p)
      d = p[:distribution] || {}
      distribution = { "method" => method }

      case method
      when "shares"
        distribution["default_shares"] = positive_or(d[:default_shares], 1.0)
      when "per_ticket"
        distribution["per_ticket_rate"] = positive_or(d[:per_ticket_rate], 1.0)
      when "per_ticket_guaranteed"
        distribution["per_ticket_rate"] = positive_or(d[:per_ticket_rate], 1.0)
        distribution["minimum"] = d[:minimum].to_f
      when "flat_fee"
        distribution["flat_amount"] = d[:flat_amount].to_f
      when "per_act"
        act_mode = d[:act_mode].to_s
        act_mode = "tiers" unless PayoutScheme::ACT_MODES.include?(act_mode)
        distribution["act_mode"] = act_mode

        case act_mode
        when "simple"
          distribution["per_act_rate"] = d[:per_act_rate].to_f
        when "schedule"
          # Legacy shape (the wizard no longer offers it, stored rules still
          # rebuild). Rows are positional: the first amount is the first act's
          # rate. Past the end of the list, additional_act_rate applies (blank =
          # those acts pay nothing). Rows arrive as bare amounts, or as the
          # stored { act:, amount: } hashes when rebuilt from saved rules.
          rows = d[:act_rates].is_a?(Hash) ? d[:act_rates].values : Array(d[:act_rates])
          distribution["act_rates"] = rows.each_with_index.map do |row, index|
            amount = row.is_a?(Hash) ? row[:amount] : row
            { "act" => index + 1, "amount" => amount.to_f }
          end
          distribution["additional_act_rate"] = d[:additional_act_rate].presence&.to_f
        else
          # "This many acts pays this much in total"; blank/zero rows dropped,
          # stored sorted. Past the last row each further act adds
          # additional_act_rate (blank = the last row is the ceiling).
          rows = d[:tiers].is_a?(Hash) ? d[:tiers].values : Array(d[:tiers])
          distribution["tiers"] = rows.filter_map do |tier|
            acts = tier[:acts].to_i
            next if acts <= 0

            { "acts" => acts, "amount" => tier[:amount].to_f }
          end.sort_by { |tier| tier["acts"] }
          distribution["additional_act_rate"] = d[:additional_act_rate].to_f if d[:additional_act_rate].present?
        end

        # Show roles priced by name (see PayoutScheme::ROLE_STACKINGS). Only
        # written when a row is fully filled in: a prefilled name left without
        # an amount stays unpriced (the show payout page nudges about it),
        # while a typed "0" is a real price. The last row for a name wins.
        rows = d[:role_amounts].is_a?(Hash) ? d[:role_amounts].values : Array(d[:role_amounts])
        role_rows = rows.filter_map do |row|
          next unless row.is_a?(Hash)

          name = row[:name].to_s.squish
          next if name.blank? || row[:amount].to_s.strip.blank?

          { "name" => name, "amount" => row[:amount].to_f }
        end
        role_rows = role_rows.reverse.uniq { |row| PayoutScheme.normalize_role_name(row["name"]) }.reverse
        if role_rows.any?
          distribution["role_amounts"] = role_rows
          distribution["role_stacking"] = PayoutScheme.role_stacking("role_stacking" => d[:role_stacking])
        end
      end

      distribution
    end

    OVERRIDE_KEYS = %w[per_ticket_rate minimum shares flat_amount per_act_rate].freeze

    def build_performer_overrides(overrides)
      result = {}
      (overrides || {}).each do |key, data|
        next if key.blank? || data.blank?

        override = {}
        OVERRIDE_KEYS.each do |field|
          value = data[field.to_sym]
          override[field] = value.to_f if value.present?
        end
        result[key.to_s] = override if override.any?
      end
      result
    end

    def each_row(rows, &block)
      list = rows.is_a?(Hash) ? rows.values : Array(rows)
      list.each(&block)
    end

    def positive_or(value, default)
      f = value.to_f
      f.positive? ? f : default
    end

    def truthy?(value)
      [ true, "1", "true", "on" ].include?(value)
    end
  end
end

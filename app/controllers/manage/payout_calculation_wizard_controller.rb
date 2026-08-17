# frozen_string_literal: true

module Manage
  # The wizard that creates and edits a payout calculation (the PayoutScheme
  # record — shown to users as a "payout calculation").
  #
  # Steps: approach → amounts → before (pool approaches only) → who → review.
  # The name comes last, on the review step, prefilled with a suggestion read
  # off the calculation itself. State lives in Rails.cache like the production
  # wizard. Edit re-enters the same wizard seeded from the record. Optional
  # context carried in state:
  #   production_id — preselect this production on the "who uses it" step
  #   return_to     — where to go after saving (Pay tab, payout page…)
  class PayoutCalculationWizardController < Manage::ManageController
    before_action :ensure_user_is_manager
    before_action :load_state

    # A show that pays nobody simply has no calculation, so "not paid" isn't an
    # approach here. Legacy no_pay calculations still open (see approach_for_method).
    APPROACHES = {
      "flat" => { method: "flat_fee", name: "A flat amount each", blurb: "Everyone cast gets the same fixed amount, whatever the night takes." },
      "per_act" => { method: "per_act", name: "By the acts they perform", blurb: "Each person is paid for the number of acts they did — one rate for every act, or a table by how many they do." },
      "per_ticket" => { method: "per_ticket", name: "Per ticket sold", blurb: "A rate for every ticket sold, optionally with a guaranteed minimum." },
      "share" => { method: "equal", name: "A share of the night's money", blurb: "After the house and expenses take theirs, the rest is split — equally or by shares." }
    }.freeze

    def start
      reset_state(from: params[:id].presence && find_calculation(params[:id]),
                  duplicate: params[:duplicate].present?)
      @state[:production_id] = context_production&.id
      @state[:return_to] = safe_return_to(params[:return_to])
      save_state
      redirect_to(@state[:editing_id].present? && params[:duplicate].blank? ? wizard_path(:review) : wizard_path(:approach))
    end

    def approach
      @state[:approach] ||= default_approach
    end

    def save_approach
      approach = params[:approach].to_s
      approach = default_approach unless APPROACHES.key?(approach)
      # A new approach starts from its own starter numbers.
      @state[:distribution] = starter_distribution(approach) if @state[:approach] != approach || @state[:distribution].blank?
      @state[:approach] = approach
      save_state
      redirect_to next_after(:approach)
    end

    def amounts
      @distribution = @state[:distribution] || starter_distribution(current_approach)
      @legacy_no_pay = @state[:legacy_no_pay].present?
    end

    def save_amounts
      # Stored in the same shape the rules use, so the amounts form (and the
      # review) read one shape whether we got here from a post or an edit.
      raw = amounts_from_params
      @state[:distribution] = PayoutRulesBuilder.build("method" => raw["method"], "distribution" => raw)["distribution"]
      @state.delete(:legacy_no_pay)
      save_state
      redirect_to next_after(:amounts)
    end

    def before
      redirect_to next_after(:before) and return unless pool_approach?
      @state[:house_percentage] ||= 0
      @state[:expenses_first] = false if @state[:expenses_first].nil?
      @state[:individual_allocations] ||= []
      @people = Current.organization.people.order(:name).to_a
    end

    def save_before
      @state[:house_percentage] = params[:house_percentage].to_f.clamp(0, 100)
      @state[:expenses_first] = params[:expenses_first] == "1"
      @state[:individual_allocations] = Array(params[:individual_allocations]&.values).filter_map do |row|
        next if row[:person_id].blank? || row[:percentage].blank?
        { person_id: row[:person_id].to_i, percentage: row[:percentage].to_f, label: row[:label].to_s.strip }
      end
      save_state
      redirect_to next_after(:before)
    end

    def who
      load_productions
      @default_production_ids = default_production_ids
      @starting_on = @state[:starting_on].presence
    end

    def save_who
      @state[:default_production_ids] = Current.organization.productions.where(id: Array(params[:default_production_ids]).map(&:to_i)).pluck(:id)
      @state[:starting_on] = params[:starting] == "date" ? parse_date(params[:starting_on])&.iso8601 : nil
      save_state
      redirect_to next_after(:who)
    end

    def review
      @rules = rules_from_state
      @summary_calculation = PayoutScheme.new(rules: @rules)
      @name = @state[:name].presence || PayoutScheme.suggested_name(@rules)
      @description = @state[:description].to_s
      @productions = Current.organization.productions.where(id: default_production_ids).order(:name).to_a
      @starting_on = @state[:starting_on].presence
    end

    def save
      @state[:name] = params[:name].to_s.strip
      @state[:description] = params[:description].to_s.strip
      save_state
      if @state[:name].blank?
        flash.now[:alert] = "Give the calculation a name — that's how you'll pick it from a list."
        review
        @name = ""
        render :review, status: :unprocessable_entity and return
      end

      calculation = if @state[:editing_id].present?
        find_calculation(@state[:editing_id])
      else
        PayoutScheme.new(organization: Current.organization)
      end
      calculation.assign_attributes(name: @state[:name], description: @state[:description], rules: rules_from_state)

      chosen_ids = Current.organization.productions.where(id: default_production_ids).pluck(:id)
      starting_on = parse_date(@state[:starting_on])

      ActiveRecord::Base.transaction do
        calculation.save!

        Current.organization.productions.where(id: chosen_ids).find_each do |production|
          calculation.make_production_scheme!(production, starting_on: starting_on)
        end
        # Productions this calculation used to be the default for, now unchecked.
        # (No NULLs in the NOT IN list — SQL would match nothing.)
        PayoutSchemeDefault.where(payout_scheme: calculation).where.not(production_id: chosen_ids)
                           .includes(:production).find_each do |default|
          PayoutScheme.clear_production_scheme!(default.production) if default.production
        end
      end

      return_to = @state[:return_to]
      clear_state
      redirect_to(return_to.presence || manage_money_payout_calculation_path(calculation),
                  notice: "#{calculation.name} is ready.")
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.record.errors.full_messages.to_sentence
      review
      render :review, status: :unprocessable_entity
    end

    def cancel
      return_to = @state[:return_to]
      clear_state
      redirect_to return_to.presence || manage_money_payout_calculations_path
    end

    private

    # ---- steps ---------------------------------------------------------------

    STEPS = %i[approach amounts before who review].freeze

    def steps_for_state
      steps = [ :approach, :amounts ]
      steps << :before if pool_approach?
      steps << :who
      steps << :review
    end
    helper_method :steps_for_state

    # The next step in this state's sequence. Works for a step the state skips
    # too (before when there's no pool): the first step in sequence that comes
    # after it.
    def next_after(step)
      position = STEPS.index(step) || -1
      following = steps_for_state.find { |s| STEPS.index(s) > position }
      wizard_path(following || :review)
    end

    def wizard_path(step)
      public_send("manage_money_payout_calculation_wizard_#{step}_path")
    end
    helper_method :wizard_path

    def current_approach
      @state[:approach].presence || default_approach
    end
    helper_method :current_approach

    def pool_approach?
      current_approach == "share"
    end

    def default_approach
      context_production&.act_based? ? "per_act" : "flat"
    end

    def context_production
      return @context_production if defined?(@context_production)
      id = params[:production_id].presence || @state&.dig(:production_id)
      @context_production = id && Current.organization.productions.find_by(id: id)
    end
    helper_method :context_production

    # ---- who uses it -----------------------------------------------------------

    def load_productions
      @productions = Current.organization.productions.order(:name).to_a
      @current_calculations = @productions.to_h { |p| [ p.id, PayoutScheme.current_default_for_production(p) ] }
    end

    # Until the "who" step has been answered, the production the wizard was
    # opened from (a Pay tab, the production wizard) is preselected.
    def default_production_ids
      return Array(@state[:default_production_ids]).map(&:to_i) if @state.key?(:default_production_ids)
      [ @state[:production_id] ].compact.map(&:to_i)
    end

    def parse_date(value)
      return nil if value.blank?
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    # ---- rules -----------------------------------------------------------------

    def rules_from_state
      approach = APPROACHES[current_approach]
      distribution = (@state[:distribution] || starter_distribution(current_approach)).to_h.stringify_keys
      PayoutRulesBuilder.build(
        "method" => distribution["method"] || approach[:method],
        "distribution" => distribution,
        "house_percentage" => @state[:house_percentage],
        "expenses_first" => @state[:expenses_first] ? "1" : "0",
        "individual_allocations" => Array(@state[:individual_allocations]).each_with_index.to_h { |row, i| [ i.to_s, row.to_h.stringify_keys ] }
      )
    end

    # What the amounts form posts, normalised for the builder. The method
    # itself can be refined here (per_ticket ↔ guaranteed, equal ↔ shares).
    def amounts_from_params
      d = (params[:distribution] || {}).to_unsafe_h
      case current_approach
      when "per_ticket"
        method = d["guarantee_minimum"] == "1" ? "per_ticket_guaranteed" : "per_ticket"
        { "method" => method, "per_ticket_rate" => d["per_ticket_rate"], "minimum" => d["minimum"] }
      when "share"
        method = d["split"] == "shares" ? "shares" : "equal"
        { "method" => method, "default_shares" => d["default_shares"] }
      when "per_act"
        d.slice("act_mode", "per_act_rate", "act_rates", "additional_act_rate", "tiers").merge("method" => "per_act")
      else
        { "method" => "flat_fee", "flat_amount" => d["flat_amount"] }
      end
    end

    def starter_distribution(approach)
      case approach
      when "per_act" then { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25 }
      when "per_ticket" then PayoutScheme::PRESETS.dig(:per_ticket_guaranteed, :rules, :distribution).to_h.deep_stringify_keys
      when "share" then PayoutScheme::PRESETS.dig(:even_split, :rules, :distribution).to_h.deep_stringify_keys
      else PayoutScheme::PRESETS.dig(:flat_fee, :rules, :distribution).to_h.deep_stringify_keys
      end
    end

    def approach_for_method(method)
      case method.to_s
      when "no_pay", "flat_fee" then "flat"
      when "per_act" then "per_act"
      when "per_ticket", "per_ticket_guaranteed" then "per_ticket"
      else "share"
      end
    end

    # ---- state ---------------------------------------------------------------

    def load_state
      @state = (Rails.cache.read(cache_key) || {}).with_indifferent_access
    end

    def save_state
      Rails.cache.write(cache_key, @state.to_h, expires_in: 24.hours)
    end

    def clear_state
      Rails.cache.delete(cache_key)
    end

    def cache_key
      "payout_calculation_wizard:#{Current.user.id}:#{Current.organization.id}"
    end

    def reset_state(from: nil, duplicate: false)
      @state = {}.with_indifferent_access
      return unless from

      rules = (from.rules || {}).deep_stringify_keys
      dist = rules["distribution"] || {}
      alloc = rules["allocation"] || []
      @state[:editing_id] = from.id unless duplicate
      @state[:name] = duplicate ? "#{from.name} (copy)" : from.name
      @state[:description] = from.description
      @state[:approach] = approach_for_method(dist["method"])
      # A legacy "nobody is paid" calculation opens as a flat $0 — the wizard
      # doesn't offer not-paid any more; a show nobody pays has no calculation.
      if dist["method"].to_s == "no_pay"
        @state[:distribution] = { "method" => "flat_fee", "flat_amount" => 0 }
        @state[:legacy_no_pay] = true
      else
        @state[:distribution] = dist
      end
      @state[:expenses_first] = alloc.any? { |s| s["type"] == "expenses_first" }
      @state[:house_percentage] = alloc.find { |s| s["type"] == "percentage" && s["person_id"].blank? }&.dig("value").to_f
      @state[:individual_allocations] = alloc.select { |s| s["type"] == "percentage" && s["person_id"].present? }
                                             .map { |s| { person_id: s["person_id"], percentage: s["value"], label: s["label"] } }
      if duplicate
        @state[:default_production_ids] = []
      else
        defaults = from.payout_scheme_defaults.where.not(production_id: nil).to_a
        @state[:default_production_ids] = defaults.map(&:production_id).uniq
        # A dated default in the future is a switch still to come; show it.
        future = defaults.filter_map(&:effective_from).select { |d| d > Date.current }.min
        @state[:starting_on] = future&.iso8601
      end
    end

    def find_calculation(id)
      Current.organization.payout_schemes.find(id)
    end

    def safe_return_to(value)
      value.to_s.start_with?("/manage/") ? value.to_s : nil
    end
  end
end

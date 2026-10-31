# frozen_string_literal: true

module Manage
  # A production's ticketing, set up once for all its dates
  # (ProductionTicketing): its page — every date it includes, how each is
  # selling, the money — and its settings, tab by tab, each with one Save.
  # Which dates are included works the way sign-ups' repeating events do: all
  # performances, some event types, or dates picked by hand.
  class ProductionTicketingsController < Manage::TicketingBaseController
    SECTIONS = { "dates" => "Dates", "tickets" => "Tickets", "products" => "Products", "sales" => "Sales & page", "refunds" => "Refunds",
                 "codes" => "Discount codes", "comps" => "Comps", "seating" => "Seating", "pricing" => "Pricing rules" }.freeze
    CLOSE_CHOICES = [ [ "At showtime", 0 ], [ "15 minutes before", 15 ], [ "30 minutes before", 30 ], [ "1 hour before", 60 ],
                      [ "2 hours before", 120 ], [ "The day before", 1440 ] ].freeze

    before_action :set_production, except: %i[new create]
    before_action :set_section, only: %i[edit update]

    # Which production? Single-production orgs skip the picker.
    def new
      productions = sellable_productions
      return redirect_to(manage_production_ticketing_path(productions.first)) if productions.one?

      @productions = productions.order(:name).to_a
    end

    def create
      production = sellable_productions.find(params[:production_id])
      redirect_to manage_production_ticketing_path(production)
    end

    def show
      @setup = @production.production_ticketing
      @filter = params[:dates] == "past" ? "past" : "upcoming"
      scope = Current.organization.ticket_listings.where(production: @production).joins(:show)
                     .includes(:ticket_tiers, show: %i[location location_space])
      @listings = if @filter == "past"
        scope.where("shows.date_and_time < ?", Time.current).order("shows.date_and_time DESC").limit(100).to_a
      else
        scope.where("shows.date_and_time >= ?", Time.current).order("shows.date_and_time").to_a
      end
      @stats = Ticketing::ListingStats.for(@listings)
      matching = @setup&.enabled? ? @setup.matching_shows.pluck(:id).to_set : Set.new
      # Dates that stopped matching the setup but have tickets sold stay on sale.
      @unmatched = @setup&.enabled? ? @listings.select { |l| l.inherits_tiers && !matching.include?(l.show_id) && @filter == "upcoming" } : []
    end

    def edit
      @setup = @production.production_ticketing || new_setup
    end

    def update
      @setup = ProductionTicketing.for(@production)
      case @section
      when "dates" then update_dates
      when "tickets" then update_tickets
      when "sales" then update_sales
      when "refunds" then update_refunds
      when "products" then update_products
      when "comps" then update_comps
      when "seating" then update_seating
      when "pricing" then update_pricing
      else redirect_to section_path("codes")
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to section_path(@section), alert: e.record.errors.full_messages.to_sentence
    end

    def create_code
      code = Current.organization.ticket_discount_codes.new(
        production: @production, **TicketDiscountCode.attributes_from_form(params.require(:ticket_discount_code).permit(:code, :kind, :amount, :max_uses, :shared_with))
      )
      if code.save
        redirect_to section_path("codes"), notice: "#{code.code} works for every date of #{@production.name}."
      else
        redirect_to section_path("codes"), alert: code.errors.full_messages.to_sentence
      end
    end

    def destroy_code
      code = Current.organization.ticket_discount_codes.where(production: @production).find(params[:code_id])
      code.update!(active: false)
      redirect_to section_path("codes"), notice: "#{code.code} removed."
    end

    # Who sees the code beside the ticket link (TicketDiscountCode::SHARED_WITH).
    def update_code
      code = Current.organization.ticket_discount_codes.where(production: @production).find(params[:code_id])
      shared_with = params[:shared_with].to_s.presence_in(TicketDiscountCode::SHARED_WITH)
      code.update!(shared_with: shared_with) if shared_with
      redirect_to section_path("codes"), notice: "#{code.code} is shared with #{code.shared_with_words}."
    end

    private

    # Which dates, and when their sales open and close.
    def update_dates
      was = @setup.dup
      attrs = params.require(:production_ticketing).permit(:enabled, :event_matching, :schedule_mode, :opens_days_before,
                                                           :online_close_minutes, event_type_filter: [])
      attrs[:event_type_filter] ||= [] if attrs[:event_matching] == "event_types"
      ProductionTicketing.transaction do
        @setup.update!(attrs)
        choose_dates! if @setup.event_matching == "manual"
      end
      if %w[schedule_mode opens_days_before online_close_minutes].any? { |a| was.public_send(a) != @setup.public_send(a) }
        ProductionTicketingDates.reschedule!(@setup, was: was)
      end
      if was.enabled && !@setup.enabled
        ProductionTicketingDates.switch!(@setup, on: false)
        return redirect_to(section_path(@section), notice: "Off. Its dates stopped selling; turn it on to resume.")
      end
      ProductionTicketingDates.switch!(@setup, on: true) if !was.enabled && @setup.enabled
      result = ProductionTicketingDates.sync!(@setup)
      # Turned on with nothing to sell yet: say so, rather than a quiet "Saved".
      if !was.enabled && @setup.enabled
        if @setup.ticket_tiers.active.none?
          flash[:alert] = "It's on, but there are no ticket types yet: set them on the Tickets tab and the dates go on sale."
        elsif @setup.matching_shows.none?
          flash[:alert] = "It's on, but no upcoming dates are picked yet: pick them below and they go on sale."
        end
      end
      finish(result)
    end

    def choose_dates!
      ids = @production.shows.where(id: Array(params[:selected_show_ids])).pluck(:id)
      @setup.production_ticketing_shows.where.not(show_id: ids).delete_all
      (ids - @setup.production_ticketing_shows.pluck(:show_id)).each { |id| @setup.production_ticketing_shows.create!(show_id: id) }
    end

    # Ticket types, in the order they're listed; every inheriting date follows.
    def update_tickets
      @setup.update!(ticket_tiers_attributes: tier_rows)
      sync = ProductionTicketingSync.sync_all!(@setup)
      result = ProductionTicketingDates.sync!(@setup)
      flash[:alert] = "#{helpers.pluralize(sync.skipped.size, 'date')} kept more seats than you set, because they've already sold more." if sync.skipped.any?
      finish(result)
    end

    # The Seating tab: how every date sells seats (blank follows the rooms),
    # the chart, and each ticket type's zone on it.
    def update_seating
      raw = params.fetch(:production_ticketing, {}).permit(:seating_mode, :seat_chart_id)
      chart = raw[:seat_chart_id].present? ? Current.organization.seat_charts.find_by(id: raw[:seat_chart_id]) : nil
      # Dates with seats sold keep the chart those seats are on.
      stuck = @setup.production.ticket_listings.select { |l| l.seating_mode.blank? && l.seat_chart_id.nil? && l.seats_in_use? }
      if stuck.any? { |l| l.effective_seat_chart != chart || raw[:seating_mode].blank? || raw[:seating_mode] == "general" }
        return redirect_to(section_path("seating"), alert: "#{helpers.pluralize(stuck.size, 'date')} #{stuck.size == 1 ? 'has' : 'have'} seats sold on #{stuck.first.effective_seat_chart.name}. Give #{stuck.size == 1 ? 'it its' : 'them their'} own seating choice first, or refund and move those tickets.")
      end
      @setup.update!(seating_mode: raw[:seating_mode].presence, seat_chart: chart)
      if params[:zones_present] == "1" && (chart || @setup.seat_chart)
        sections = (chart || @setup.seat_chart).sections.pluck(:id)
        zones = params.fetch(:zones, {}).to_unsafe_h
        @setup.ticket_tiers.active.reject(&:bundle?).each do |tier|
          wanted = Array(zones[tier.id.to_s]).map(&:to_i) & sections
          tier.zones.where.not(seat_section_id: wanted).delete_all
          (wanted - tier.zones.pluck(:seat_section_id)).each { |sid| tier.zones.create!(seat_section_id: sid) }
        end
      end
      redirect_to section_path("seating"), notice: "Saved. #{@setup.seating_mode.present? ? "Every date sells #{RoomTicketingSetting::SEATING_MODE_LABELS[@setup.seating_mode].downcase}." : 'Each date sells the way its room says.'}"
    end

    # The Pricing rules tab (advanced ticketing §7c): add, order, switch and
    # remove rules; each type's floor and ceiling.
    def update_pricing
      case params[:pricing_action].to_s
      when "add"
        raw = params.require(:rule).permit(:name, :condition, :threshold, :days, :ticket_tier_id, :change_kind, :change_value)
        tier = raw[:ticket_tier_id].present? ? @setup.ticket_tiers.find_by(id: raw[:ticket_tier_id]) : nil
        value = raw[:change_kind] == "percent" ? raw[:change_value].to_i : (raw[:change_value].to_s.delete("$,").to_f * 100).round
        rule = @setup.price_rules.create!(organization: Current.organization, ticket_tier: tier, name: raw[:name].to_s.squish, condition: raw[:condition],
                                          threshold: raw[:threshold].to_i, days: raw[:days].to_i, change_kind: raw[:change_kind], change_value: value,
                                          position: (@setup.price_rules.maximum(:position) || 0) + 1)
        redirect_to section_path("pricing"), notice: "Added: #{rule.words}."
      when "remove"
        rule = @setup.price_rules.find(params[:rule_id])
        rule.destroy!
        redirect_to section_path("pricing"), notice: "Removed: #{rule.words}."
      when "toggle"
        rule = @setup.price_rules.find(params[:rule_id])
        rule.update!(enabled: !rule.enabled)
        redirect_to section_path("pricing"), notice: rule.enabled ? "On: #{rule.words}." : "Off: #{rule.words}."
      when "up", "down"
        rules = @setup.price_rules.in_order.to_a
        i = rules.index { |r| r.id == params[:rule_id].to_i }
        j = params[:pricing_action] == "up" ? i - 1 : i + 1
        rules[i], rules[j] = rules[j], rules[i] if i && j.between?(0, rules.size - 1)
        rules.each_with_index { |r, n| r.update_columns(position: n + 1) }
        redirect_to section_path("pricing")
      when "limits"
        limits = params.fetch(:limits, {}).to_unsafe_h
        @setup.ticket_tiers.active.each do |tier|
          row = limits[tier.id.to_s] or next
          floor = row["floor"].to_s.delete("$,").presence&.then { |v| (v.to_f * 100).round }
          ceiling = row["ceiling"].to_s.delete("$,").presence&.then { |v| (v.to_f * 100).round }
          return redirect_to(section_path("pricing"), alert: "#{tier.name}: the floor is above the ceiling.") if floor && ceiling && floor > ceiling
          tier.update!(price_floor_cents: floor, price_ceiling_cents: ceiling)
          tier.copies.update_all(price_floor_cents: floor, price_ceiling_cents: ceiling)
        end
        redirect_to section_path("pricing"), notice: "Saved the floors and ceilings."
      else
        redirect_to section_path("pricing")
      end
    end

    def update_sales
      raw = params.require(:production_ticketing)
      permitted = raw.permit(:max_per_order, :fee_mode, :low_stock_threshold, :title, :description,
                             :door_note, :age_note, :accessibility_note).to_h.transform_values(&:presence)
      permitted[:waitlist] = raw[:waitlist] == "1" if raw.key?(:waitlist)
      if raw.key?(:age_choice)
        age = AgeLimit.value_for(raw[:age_choice], raw[:age_other])
        return redirect_to(section_path("sales"), alert: "Type an age from 1 to 99.") if age == :invalid

        permitted[:minimum_age] = age
      end
      @setup.update!(permitted)
      redirect_to section_path("sales"), notice: "Saved. Dates without their own settings use these."
    end

    # The Refunds tab: its own refund policy (the switch on), or the box
    # office's (off: every field cleared).
    def update_refunds
      raw = params.require(:production_ticketing)
      attrs = if raw[:own_refund_policy] == "1"
        chosen = RefundPolicy.attributes_for(raw[:refund_choice], raw[:refund_days]) || {}
        chosen.reverse_merge(refund_window_hours: nil).merge(refund_fees: raw[:refund_fees] == "1", refund_policy_note: raw[:refund_policy_note].to_s.strip.presence)
      else
        { refund_policy: nil, refund_window_hours: nil, refund_fees: nil, refund_policy_note: nil }
      end
      @setup.update!(attrs)
      notice = @setup.refund_policy.present? ? "Saved. #{@production.name} has its own refund policy." : "Saved. #{@production.name} follows your box office's refund policy."
      redirect_to section_path("refunds"), notice: notice
    end

    # The Comps tab: its own comp rules (the switch on), or the box office's
    # (off: every field cleared). Its dates follow it (CompRules).
    def update_comps
      raw = params.require(:production_ticketing).permit(:own_comps, *CompRules::FIELDS)
      own = raw[:own_comps] == "1"
      @setup.update!(CompRules.attributes_from(raw, own: own).merge(own_comps: own))
      notice = own ? "Saved. #{@production.name} has its own comp rules: #{@setup.comp_rules_words}." : "Saved. #{@production.name} follows your box office's comp rules."
      redirect_to section_path("comps"), notice: notice
    end

    # Which of the org's products this production upsells, and (with the
    # switch on) its own prices and revenue rules for them.
    def update_products
      own = params.dig(:production_ticketing, :own_product_prices) == "1"
      rows = params[:products].respond_to?(:each_pair) ? params[:products].each_pair.to_h : {}
      products = Current.organization.ticket_products.active.ordered.to_a
      ProductionTicketing.transaction do
        @setup.update!(own_product_prices: own, products_at_door: params.dig(:production_ticketing, :products_at_door) == "1")
        position = 0
        products.each do |product|
          row = rows[product.id.to_s]
          offered = row && row.respond_to?(:[]) && row[:offered] == "1"
          link = @setup.production_ticketing_products.find_by(ticket_product_id: product.id)
          if offered
            link ||= @setup.production_ticketing_products.new(ticket_product: product)
            link.position = position
            position += 1
            if own
              link.price_cents = dollars_to_cents(row[:price])
              link.counts_toward_ticket_revenue = row[:counts_toward_ticket_revenue] == "1"
            else
              link.price_cents = nil
              link.counts_toward_ticket_revenue = nil
            end
            link.save!
          elsif link
            link.destroy!
          end
        end
      end
      offered = @setup.production_ticketing_products.count
      redirect_to section_path("products"), notice: offered.zero? ? "Saved. No products are offered at checkout." : "Saved. #{helpers.pluralize(offered, 'product')} offered at checkout for every date."
    end

    # "$45" or "45.00" → 4500; blank → nil (the product's standard price).
    def dollars_to_cents(text)
      price = text.to_s.delete("$,").strip
      price.empty? ? nil : (BigDecimal(price) * 100).round.to_i
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end

    def finish(result)
      notice = [ "Saved.", (result.summary.presence && "#{result.summary.upcase_first}.") ].compact.join(" ")
      if result.kept.any?
        flash[:alert] = "#{helpers.pluralize(result.kept.size, 'date')} no longer #{result.kept.one? ? 'matches' : 'match'} but #{result.kept.one? ? 'has' : 'have'} tickets sold, so #{result.kept.one? ? 'it stays' : 'they stay'} on sale."
      end
      redirect_to section_path(@section), notice: notice
    end

    # Rows from the Tickets tab, prices typed as dollars, in the order shown.
    def tier_rows
      rows = params.dig(:production_ticketing, :ticket_tiers_attributes)
      return {} unless rows.respond_to?(:each_pair)

      rows.each_pair.to_h do |key, row|
        row = row.permit(:id, :name, :price, :quantity, :admits, :bundle_of_tier_id, :description, :position, :sells_at, :_destroy).to_h
        price = row.delete("price").to_s.delete("$,").strip
        row["price_cents"] = price.empty? ? 0 : (BigDecimal(price) * 100).round.to_i
        row["quantity"] = row["quantity"].presence
        row["admits"] = row["admits"].presence || 1 if row.key?("admits")
        row["bundle_of_tier_id"] = row["bundle_of_tier_id"].presence if row.key?("bundle_of_tier_id")
        row["description"] = row["description"].presence
        [ key, row ]
      end
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end

    # A setup not saved yet, starting from the prices this production last
    # used (or a contract's), so the first visit isn't a blank page.
    def new_setup
      setup = ProductionTicketing.new(production: @production, organization: Current.organization)
      suggested_tiers.each_with_index { |tier, i| setup.ticket_tiers.build(tier.merge(position: i)) }
      setup
    end

    def suggested_tiers
      last = Current.organization.ticket_listings.where(production: @production).order(created_at: :desc).first
      return last.ticket_tiers.active.map { |t| { name: t.name, price_cents: t.price_cents, quantity: t.quantity } } if last

      contract = @production.contracts.order(created_at: :desc).find { |c| c.draft_ticketing["tiers"].present? }
      tiers = contract&.draft_ticketing&.dig("tiers").to_a.map do |tier|
        { name: tier["name"], price_cents: (tier["price"].to_f * 100).round, quantity: tier["quantity"].presence&.to_i }
      end
      tiers.presence || [ { name: "General admission", price_cents: 0, quantity: nil } ]
    end

    def sellable_productions
      Current.organization.productions.active.schedulable
    end

    # Scoped to the current org: a bare find here would reach another org's production.
    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_section
      @section = params[:section].presence || "dates"
      redirect_to section_path("dates") unless SECTIONS.key?(@section)
    end

    def section_path(key)
      manage_edit_production_ticketing_path(@production, section: key)
    end

    def sections
      SECTIONS.map { |key, label| { key: key, label: label, path: section_path(key) } }
    end
    helper_method :sections
  end
end

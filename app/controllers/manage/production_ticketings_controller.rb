# frozen_string_literal: true

module Manage
  # A production's ticketing, set up once for all its dates
  # (ProductionTicketing): its page — every date it includes, how each is
  # selling, the money — and its settings, tab by tab, each with one Save.
  # Which dates are included works the way sign-ups' repeating events do: all
  # performances, some event types, or dates picked by hand.
  class ProductionTicketingsController < Manage::TicketingBaseController
    SECTIONS = { "dates" => "Dates", "tickets" => "Tickets", "sales" => "Sales & page", "codes" => "Discount codes" }.freeze
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
      else redirect_to section_path("codes")
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to section_path(@section), alert: e.record.errors.full_messages.to_sentence
    end

    def create_code
      code = Current.organization.ticket_discount_codes.new(
        production: @production, **TicketDiscountCode.attributes_from_form(params.require(:ticket_discount_code).permit(:code, :kind, :amount, :max_uses))
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
      finish(ProductionTicketingDates.sync!(@setup))
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

    def update_sales
      permitted = params.require(:production_ticketing).permit(:max_per_order, :fee_mode, :title, :description,
                                                               :door_note, :age_note, :accessibility_note)
      @setup.update!(permitted.to_h.transform_values(&:presence))
      redirect_to section_path("sales"), notice: "Saved. Dates without their own settings use these."
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
        row = row.permit(:id, :name, :price, :quantity, :description, :position, :_destroy).to_h
        price = row.delete("price").to_s.delete("$,").strip
        row["price_cents"] = price.empty? ? 0 : (BigDecimal(price) * 100).round.to_i
        row["quantity"] = row["quantity"].presence
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

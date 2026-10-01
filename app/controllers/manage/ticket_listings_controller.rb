# frozen_string_literal: true

module Manage
  # Shows on sale: putting a production's dates on sale, and running each one —
  # prices and seats, sales window, fee switch, discount codes. Nothing goes
  # on sale by itself; a manager puts it on sale or schedules when sales open.
  class TicketListingsController < Manage::TicketingBaseController
    FILTERS = %w[upcoming drafts past].freeze
    STATUS_ACTIONS = {
      "on_sale" => %w[draft paused closed],
      "paused" => %w[on_sale],
      "closed" => %w[on_sale paused]
    }.freeze

    before_action :set_listing, only: %i[edit update change_status destroy create_code destroy_code]

    def index
      @filter = params[:filter].presence_in(FILTERS) || "upcoming"
      scope = Current.organization.ticket_listings.joins(:show)
                     .includes(:ticket_tiers, show: %i[production location location_space])
      @listings =
        case @filter
        when "drafts" then scope.where(status: "draft").order("shows.date_and_time")
        when "past" then scope.where("shows.date_and_time < ?", Time.current).order("shows.date_and_time DESC").limit(100)
        else scope.where("shows.date_and_time >= ?", Time.current).where.not(status: "draft").order("shows.date_and_time")
        end
    end

    # Which production? Single-production orgs skip the picker.
    def new
      productions = sellable_productions
      if params[:production_id].present?
        @production = productions.find(params[:production_id])
        @shows = @production.shows.where(canceled: false, event_type: EventTypes.revenue_event_types)
                            .where("date_and_time >= ?", Time.current)
                            .includes(:ticket_listing, :location_space).order(:date_and_time)
        @tier_rows = suggested_tiers(@production)
      elsif productions.one?
        redirect_to manage_new_ticket_listing_path(production_id: productions.first.id)
      else
        @productions = productions.order(:name).to_a
        render :select_production
      end
    end

    def select_production
      production = sellable_productions.find(params[:production_id])
      redirect_to manage_new_ticket_listing_path(production_id: production.id)
    end

    def create
      production = sellable_productions.find(params[:production_id])
      shows = production.shows.where(id: Array(params[:show_ids]), canceled: false).order(:date_and_time).to_a
      tiers = TicketListingBuilder.parse_tiers(tier_rows)
      status, on_sale_at = opening_choice

      result = TicketListingBuilder.create_for!(shows: shows, tiers: tiers, status: status, on_sale_at: on_sale_at)
      redirect_to manage_ticket_listings_path(filter: status == "draft" ? "drafts" : "upcoming"),
                  notice: created_notice(result, status, on_sale_at)
    rescue ArgumentError => e
      redirect_to manage_new_ticket_listing_path(production_id: production&.id), alert: e.message
    end

    def edit; end

    def update
      attrs = listing_params
      if @listing.update(attrs)
        redirect_to manage_edit_ticket_listing_path(@listing), notice: "Saved."
      else
        flash.now[:alert] = @listing.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Put on sale, pause, resume, close sales. Cancelling (with refunds) is
    # its own flow.
    def change_status
      to = params[:status].to_s
      unless STATUS_ACTIONS.fetch(to, []).include?(@listing.status)
        redirect_to manage_edit_ticket_listing_path(@listing), alert: "That can't be done from here." and return
      end

      attrs = { status: to }
      attrs[:on_sale_at] = nil if to == "on_sale" && @listing.on_sale_at&.future? && params[:now] == "1"
      @listing.update!(attrs)
      redirect_to manage_edit_ticket_listing_path(@listing), notice: status_notice(to)
    end

    def destroy
      if @listing.destroy
        redirect_to manage_ticket_listings_path(filter: "drafts"), notice: "Removed #{@listing.display_title} from Ticketing."
      else
        redirect_to manage_edit_ticket_listing_path(@listing), alert: @listing.errors.full_messages.to_sentence
      end
    end

    def create_code
      code = Current.organization.ticket_discount_codes.new(code_params.merge(ticket_listing: @listing))
      if code.save
        redirect_to manage_edit_ticket_listing_path(@listing, anchor: "discount-codes"), notice: "Added #{code.code}."
      else
        redirect_to manage_edit_ticket_listing_path(@listing, anchor: "discount-codes"), alert: code.errors.full_messages.to_sentence
      end
    end

    # Codes that have been used are switched off, never deleted: orders keep
    # saying which code they used.
    def destroy_code
      code = @listing.ticket_discount_codes.find(params[:code_id])
      if code.ticket_orders.exists?
        code.update!(active: false)
      else
        code.destroy!
      end
      redirect_to manage_edit_ticket_listing_path(@listing, anchor: "discount-codes"), notice: "#{code.code} no longer works."
    end

    private

    # Scoped to the current org: a bare find here would reach another org's show.
    def set_listing
      @listing = Current.organization.ticket_listings.find(params[:id])
    end

    def sellable_productions
      Current.organization.productions.active.schedulable
    end

    # The prices to start from: this production's latest listing, then a
    # contract's ticket tiers, then one blank General admission row.
    def suggested_tiers(production)
      last = Current.organization.ticket_listings.where(production: production).order(created_at: :desc).first
      rows = if last
        last.ticket_tiers.active.map { |t| { name: t.name, price: format("%.2f", t.price_cents / 100.0), quantity: t.quantity } }
      else
        contract_tiers(production)
      end
      rows = [ { name: "General admission", price: "", quantity: nil } ] if rows.blank?
      rows + Array.new([ 4 - rows.size, 1 ].max) { { name: "", price: "", quantity: nil } }
    end

    def contract_tiers(production)
      contract = production.contracts.order(created_at: :desc).find { |c| c.draft_ticketing["tiers"].present? }
      return [] unless contract

      contract.draft_ticketing["tiers"].map do |tier|
        { name: tier["name"], price: tier["price"].present? ? format("%.2f", tier["price"].to_f) : "", quantity: tier["quantity"] }
      end
    end

    def tier_rows
      rows = params[:tiers]
      return [] unless rows.respond_to?(:each_value)

      rows.each_value.map { |row| row.permit(:name, :price, :quantity).to_h }
    end

    def opening_choice
      case params[:opening]
      when "now" then [ "on_sale", nil ]
      when "scheduled"
        at = Time.zone.parse(params[:on_sale_at].to_s)
        raise ArgumentError, "Pick when sales open" unless at
        [ "on_sale", at ]
      else [ "draft", nil ]
      end
    end

    def created_notice(result, status, on_sale_at)
      count = ActionController::Base.helpers.pluralize(result.created.size, "show")
      skipped = result.skipped.any? ? " #{result.skipped.size} already had tickets and were left alone." : ""
      lead =
        if status == "draft" then "#{count} ready as drafts. Put them on sale when you're ready."
        elsif on_sale_at then "#{count} go on sale #{I18n.l(on_sale_at, format: :long)}."
        else "#{count} on sale now."
        end
      lead + skipped
    end

    def status_notice(to)
      { "on_sale" => "On sale.", "paused" => "Sales paused.", "closed" => "Online sales closed." }.fetch(to)
    end

    def listing_params
      permitted = params.require(:ticket_listing).permit(
        :title, :description, :image, :on_sale_at, :off_sale_at, :capacity, :max_per_order, :fee_mode,
        :door_note, :age_note, :accessibility_note,
        ticket_tiers_attributes: %i[id name price quantity description _destroy]
      )
      permitted[:fee_mode] = permitted[:fee_mode].presence if permitted.key?(:fee_mode)
      permitted[:capacity] = permitted[:capacity].presence if permitted.key?(:capacity)
      permitted[:max_per_order] = permitted[:max_per_order].presence if permitted.key?(:max_per_order)
      if permitted[:ticket_tiers_attributes]
        permitted[:ticket_tiers_attributes] = tier_attributes(permitted[:ticket_tiers_attributes])
      end
      permitted
    end

    # Prices typed as dollars; a sold tier asked to go is archived instead, so
    # its tickets keep their tier.
    def tier_attributes(rows)
      rows.to_h.transform_values do |row|
        row = row.to_h
        price = row.delete("price").to_s.delete("$,").strip
        row["price_cents"] = price.empty? ? 0 : (BigDecimal(price) * 100).round.to_i
        row["quantity"] = row["quantity"].presence
        if row["_destroy"] == "1" && row["id"].present? && @listing.tickets.where(ticket_tier_id: row["id"]).exists?
          row.delete("_destroy")
          row["archived_at"] = Time.current
        end
        row
      end
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end

    def code_params
      raw = params.require(:ticket_discount_code).permit(:code, :kind, :amount, :max_uses)
      amount = raw[:amount].to_s.delete("$,%").strip
      attrs = { code: raw[:code], kind: raw[:kind].presence_in(TicketDiscountCode::KINDS) || "fixed", max_uses: raw[:max_uses].presence }
      if attrs[:kind] == "percent"
        attrs[:percent] = amount.presence && BigDecimal(amount)
      else
        attrs[:amount_cents] = amount.presence && (BigDecimal(amount) * 100).round.to_i
      end
      attrs
    rescue ArgumentError
      { code: raw[:code], kind: "fixed" }
    end
  end
end

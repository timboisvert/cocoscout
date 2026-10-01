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

    GUEST_FILTERS = %w[all waiting in comps refunded].freeze

    before_action :set_listing, only: %i[show guests door_list edit update change_status destroy create_code destroy_code cancel_review cancel]

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

    # One show's tickets: the numbers (Ticketing::ListingStats), the guest
    # list, and what to do next.
    def show
      @stats = Ticketing::ListingStats.of(@listing)
      @guest_filter = params[:guests].presence_in(GUEST_FILTERS) || "all"
      @query = params[:q].to_s.strip
      @guest_orders = guest_orders(@guest_filter, @query)
    end

    # Everyone holding tickets, as a spreadsheet.
    def guests
      require "csv"
      csv = CSV.generate do |rows|
        rows << [ "Name", "Email", "Phone", "Order", "Tickets", "Ticket types", "Checked in", "How", "Note", "OK to email news" ]
        guest_orders("all", "").each do |order|
          held = held_tickets(order)
          rows << [ order.buyer_name, order.buyer_email, order.buyer_phone, order.code, held.size,
                    held.group_by(&:ticket_tier).map { |tier, ts| "#{ts.size} #{tier.name}" }.join("; "),
                    held.count(&:checked_in?), Ticketing::ListingStats::CHANNELS.fetch(order.channel, order.channel),
                    order.note, order.marketing_opt_in ? "Yes" : "No" ]
        end
      end
      send_data csv, type: "text/csv", filename: "guests-#{@listing.slug}.csv"
    end

    # The guest list on paper, by last name, for a door with no signal.
    def door_list
      @rows = guest_orders("all", "").map do |order|
        held = held_tickets(order)
        { name: order.buyer_name.presence || "No name", count: held.size, inside: held.count(&:checked_in?),
          tiers: held.group_by(&:ticket_tier).map { |tier, ts| "#{ts.size} × #{tier.name}" }.join(", "),
          code: order.code, comp: order.channel == "comp" }
      end.sort_by { |row| [ row[:name].split.last.to_s.downcase, row[:name].downcase ] }
      render layout: false
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
      redirect_back_or_to manage_ticket_listing_path(@listing), notice: status_notice(to)
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

    # Canceling a show that sold tickets: who gets refunded, and the email
    # they'll get (editable), before anything happens.
    def cancel_review
      if @listing.status == "canceled"
        redirect_to manage_edit_ticket_listing_path(@listing), notice: "This show's ticket sales are already canceled." and return
      end
      if show_started?
        redirect_to manage_edit_ticket_listing_path(@listing), alert: "This show has already started, so it can't be canceled here." and return
      end

      @draft = TicketShowCancellation.draft(@listing)
    end

    def cancel
      if @listing.status == "canceled" || show_started?
        redirect_to manage_edit_ticket_listing_path(@listing) and return
      end

      count = TicketShowCancellation.orders(@listing).count
      TicketShowCancellation.start!(@listing, subject: params[:subject], body: params[:body], by: Current.user,
                                              cancel_show: params[:cancel_show] == "1")
      notice = count.zero? ? "Ticket sales canceled." : "Ticket sales canceled. Refunds are on their way to #{helpers.pluralize(count, 'buyer')}."
      redirect_to manage_edit_ticket_listing_path(@listing), notice: notice
    end

    private

    def show_started?
      @listing.show.date_and_time <= Time.current
    end

    def held_tickets(order)
      order.tickets.select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    end

    # The show's orders for the guest list, narrowed by a filter and a search.
    def guest_orders(filter, query)
      orders = @listing.ticket_orders.where(status: %w[paid partially_refunded refunded])
                       .includes(tickets: :ticket_tier).order(:buyer_name, :id).to_a
      if query.present?
        q = query.downcase
        orders = orders.select { |o| [ o.buyer_name, o.buyer_email, o.code ].compact.any? { |v| v.downcase.include?(q) } }
      end
      case filter
      when "waiting" then orders.select { |o| held_tickets(o).any? { |t| !t.checked_in? } }
      when "in" then orders.select { |o| held_tickets(o).any?(&:checked_in?) }
      when "comps" then orders.select { |o| o.channel == "comp" && held_tickets(o).any? }
      when "refunded" then orders.select { |o| o.status.in?(%w[refunded partially_refunded]) }
      else orders.select { |o| held_tickets(o).any? }
      end
    end

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

# frozen_string_literal: true

module Manage
  # Ticketing's Shows: the productions selling tickets (each opens its
  # production's ticketing page, ProductionTicketingsController), and running
  # each date — its numbers and guests, prices and seats, sales window, fee
  # switch, discount codes.
  class TicketListingsController < Manage::TicketingBaseController
    STATUS_ACTIONS = {
      "on_sale" => %w[draft paused closed],
      "paused" => %w[on_sale],
      "closed" => %w[on_sale paused]
    }.freeze

    GUEST_FILTERS = %w[all waiting in comps refunded].freeze
    # A date's Settings, a tab each with its own Save.
    SETTINGS = { "tickets" => "Tickets", "products" => "Products", "sales" => "Sales", "page" => "Page", "codes" => "Discount codes" }.freeze

    before_action :set_listing, only: %i[show guests door_list edit update change_status destroy create_code destroy_code cancel
                                           change_review tell_change mark_change_told outside_sales]
    before_action :set_settings_section, only: %i[edit update]

    # Productions first: every production selling tickets, by its next date.
    def index
      org = Current.organization
      ids = org.ticket_listings.distinct.pluck(:production_id) | ProductionTicketing.where(organization: org).pluck(:production_id)
      upcoming = org.ticket_listings.joins(:show).where.not(status: "canceled").where(shows: { canceled: false })
                    .where("shows.date_and_time >= ?", Time.current)
      @next_dates = upcoming.group(:production_id).minimum("shows.date_and_time")
      @date_counts = upcoming.group(:production_id).count
      @sold_this_week = Ticket.joins(:ticket_order, :ticket_listing).where(ticket_listing_id: upcoming.select(:id), status: Ticket::SOLD_STATUSES)
                              .where(ticket_orders: { paid_at: 7.days.ago.. }).group("ticket_listings.production_id").count
      @productions = org.productions.where(id: ids).includes(:production_ticketing, posters: { image_attachment: :blob }).to_a
                        .sort_by { |production| [ @next_dates[production.id] ? 0 : 1, @next_dates[production.id] || Time.current, production.name ] }
    end

    # One show's tickets: the numbers (Ticketing::ListingStats), the guest
    # list, and what to do next.
    def show
      @stats = Ticketing::ListingStats.of(@listing)
      @guest_filter = params[:guests].presence_in(GUEST_FILTERS) || "all"
      @query = params[:q].to_s.strip
      @guest_orders = guest_orders(@guest_filter, @query)
      # The Sold elsewhere modal: the organization's other sites and what each sold here, by type.
      @outside_sources = Current.organization.ticket_sources.hand_made.active.ordered.to_a
      @outside_rows = @listing.ticket_outside_sales.index_by { |row| [ row.ticket_source_id, row.ticket_tier_id ] }
    end

    # Everyone holding tickets, as a spreadsheet.
    def guests
      require "csv"
      csv = CSV.generate do |rows|
        rows << [ "Name", "Email", "Phone", "Order", "Tickets", "Ticket types", "Products", "Checked in", "How", "Note" ]
        guest_orders("all", "").each do |order|
          held = held_tickets(order)
          rows << [ order.buyer_name, order.buyer_email, order.buyer_phone, order.code, held.size,
                    held.group_by(&:ticket_tier).map { |tier, ts| "#{ts.size} #{tier.name}" }.join("; "),
                    order.ticket_order_items.select(&:sold?).map(&:label).join("; "),
                    held.count(&:checked_in?), Ticketing::ListingStats::CHANNELS.fetch(order.channel, order.channel),
                    order.note ]
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
          products: order.ticket_order_items.select(&:sold?).map(&:label).join(", "),
          code: order.code, comp: order.channel == "comp" }
      end.sort_by { |row| [ row[:name].split.last.to_s.downcase, row[:name].downcase ] }
      render layout: false
    end

    def edit; end

    # Tickets sold on other sites (Ticket Tailor, Eventbrite), by ticket type
    # and site. Each type's seats here shrink by its count
    # (Ticketing::Inventory#outside), and each site's Show Financials row is
    # fed from them (TicketOutsideSales), so settlement already has the
    # numbers. A new site becomes a ticket source for the whole organization.
    def outside_sales
      org = Current.organization
      rows = params.fetch(:sales, {}).to_unsafe_h
      new_rows = rows.delete("new")
      new_name = params[:new_source_name].to_s.squish
      if new_name.present?
        source = org.ticket_sources.find_by("LOWER(name) = ?", new_name.downcase) || org.ticket_sources.create!(name: new_name, position: org.ticket_sources.count)
        source.restore! if source.archived?
        rows[source.id.to_s] = new_rows || {}
      end
      TicketOutsideSales.record!(@listing, rows)
      total = @listing.inventory.outside_sold
      redirect_to manage_ticket_listing_path(@listing),
                  notice: total.positive? ? "#{helpers.pluralize(total, 'ticket')} sold elsewhere, off this show's seats." : "No tickets sold elsewhere."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_ticket_listing_path(@listing), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      attrs = listing_params
      notice = "Saved."
      # The Tickets tab's switch: this date's own prices, or the production's.
      if @section == "tickets" && (setup = @listing.production_ticketing)
        own = params.dig(:ticket_listing, :own_prices) == "1"
        if own && @listing.inherits_tiers
          give_own_prices!
          notice = "Saved. This date has its own prices now; changes to the production's won't reach it."
        elsif !own && !@listing.inherits_tiers
          use_production_prices!(setup)
          return redirect_to(settings_path(@section), notice: "This date uses #{helpers.possessive(@listing.production.name)} prices again.")
        elsif !own
          return redirect_to(settings_path(@section), notice: notice)
        end
      end

      if @listing.update(attrs)
        redirect_to settings_path(@section), notice: notice
      else
        flash.now[:alert] = @listing.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    # Put on sale, pause, resume, close sales. Cancelling (with refunds) is
    # its own flow.
    def change_status
      to = params[:status].to_s
      unless STATUS_ACTIONS.fetch(to, []).include?(@listing.status)
        redirect_to manage_ticket_listing_path(@listing), alert: "That can't be done from here." and return
      end

      attrs = { status: to }
      attrs[:on_sale_at] = nil if to == "on_sale" && @listing.on_sale_at&.future? && params[:now] == "1"
      @listing.update!(attrs)
      redirect_back_or_to manage_ticket_listing_path(@listing), notice: status_notice(to)
    end

    def destroy
      if @listing.destroy
        redirect_to manage_production_ticketing_path(@listing.production), notice: "Removed #{@listing.display_title} from Ticketing."
      else
        redirect_to settings_path("sales"), alert: @listing.errors.full_messages.to_sentence
      end
    end

    def create_code
      code = Current.organization.ticket_discount_codes.new(code_params.merge(ticket_listing: @listing))
      if code.save
        redirect_to settings_path("codes"), notice: "Added #{code.code}."
      else
        redirect_to settings_path("codes"), alert: code.errors.full_messages.to_sentence
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
      redirect_to settings_path("codes"), notice: "#{code.code} no longer works."
    end

    # A show already canceled on the calendar whose buyers still hold tickets:
    # refund them now (from the show's cancel screen in Shows & Events, where
    # canceling happens).
    def cancel
      cancel_path = manage_cancel_show_form_path(@listing.production, @listing.show)
      if @listing.status == "canceled" || show_started? || !@listing.show.canceled
        redirect_to cancel_path and return
      end

      count = TicketShowCancellation.orders(@listing).count
      TicketShowCancellation.start!(@listing, subject: params[:subject], body: params[:body], by: Current.user)
      redirect_to cancel_path, notice: "Refunds are on their way to #{helpers.pluralize(count, 'ticket buyer')}."
    end

    # The show moved after people bought: who to tell, and the email they'll
    # get (editable), before anything goes out.
    def change_review
      unless TicketShowChange.pending?(@listing)
        redirect_to manage_ticket_listing_path(@listing), notice: "Everyone who bought knows the show's date, time and place." and return
      end

      @draft = TicketShowChange.draft(@listing)
    end

    def tell_change
      count = TicketShowChange.orders(@listing).count
      redirect_to manage_ticket_listing_path(@listing) and return if count.zero?
      if params[:subject].blank? || params[:body].blank?
        redirect_to manage_ticket_listing_change_path(@listing), alert: "Write a subject and a message first." and return
      end

      TicketShowChange.start!(@listing, subject: params[:subject], body: params[:body])
      redirect_to manage_ticket_listing_path(@listing), notice: "Emailing #{helpers.pluralize(count, 'buyer')} about the change."
    end

    def mark_change_told
      count = TicketShowChange.mark_told!(@listing)
      redirect_to manage_ticket_listing_path(@listing), notice: "Marked #{helpers.pluralize(count, 'buyer')} as told. No emails went out."
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
      orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID)
                       .includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass]).order(:buyer_name, :id).to_a
      if query.present?
        q = query.downcase
        orders = orders.select { |o| [ o.buyer_name, o.buyer_email, o.code ].compact.any? { |v| v.downcase.include?(q) } }
      end
      case filter
      when "waiting" then orders.select { |o| held_tickets(o).any? { |t| !t.checked_in? } }
      when "in" then orders.select { |o| held_tickets(o).any?(&:checked_in?) }
      when "comps" then orders.select { |o| o.channel == "comp" && held_tickets(o).any? }
      when "refunded" then orders.select { |o| o.status.in?(%w[refunded partially_refunded exchanged]) }
      else orders.select { |o| held_tickets(o).any? }
      end
    end

    # Scoped to the current org: a bare find here would reach another org's show.
    def set_listing
      @listing = Current.organization.ticket_listings.find(params[:id])
    end

    # This date's ticket types stop following the production's: the copies
    # it holds become its own, to edit here.
    def give_own_prices!
      @listing.update!(inherits_tiers: false)
      @listing.ticket_tiers.update_all(source_tier_id: nil, updated_at: Time.current)
    end

    # Back to the production's: this date's own types go (kept only where a
    # ticket was sold on one), and fresh copies of the production's take over.
    def use_production_prices!(setup)
      own = @listing.ticket_tiers.active.to_a
      @listing.update!(inherits_tiers: true)
      own.each(&:retire!)
      ProductionTicketingSync.sync!(@listing, setup)
    end

    def set_settings_section
      @section = params[:section].presence || "tickets"
      redirect_to settings_path("tickets") unless SETTINGS.key?(@section)
    end

    def settings_path(section)
      manage_edit_ticket_listing_path(@listing, section: section)
    end

    def settings_sections
      SETTINGS.map { |key, label| { key: key, label: label, path: settings_path(key) } }
    end
    helper_method :settings_sections

    def status_notice(to)
      { "on_sale" => "On sale.", "paused" => "Sales paused.", "closed" => "Online sales closed." }.fetch(to)
    end

    def listing_params
      permitted = params.require(:ticket_listing).permit(
        :title, :description, :on_sale_at, :off_sale_at, :max_per_order, :fee_mode, :low_stock_threshold,
        :door_note, :age_note, :accessibility_note, :sell_products,
        ticket_tiers_attributes: %i[id name price quantity admits bundle_of_tier_id description position _destroy]
      )
      permitted[:fee_mode] = permitted[:fee_mode].presence if permitted.key?(:fee_mode)
      permitted[:max_per_order] = permitted[:max_per_order].presence if permitted.key?(:max_per_order)
      permitted[:low_stock_threshold] = permitted[:low_stock_threshold].presence if permitted.key?(:low_stock_threshold)
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
        row["admits"] = row["admits"].presence || 1 if row.key?("admits")
        row["bundle_of_tier_id"] = row["bundle_of_tier_id"].presence if row.key?("bundle_of_tier_id")
        if row["_destroy"] == "1" && row["id"].present? &&
           @listing.tickets.where(ticket_tier_id: row["id"]).or(@listing.tickets.where(bundle_tier_id: row["id"])).exists?
          row.delete("_destroy")
          row["archived_at"] = Time.current
        end
        row
      end
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end

    def code_params
      TicketDiscountCode.attributes_from_form(params.require(:ticket_discount_code).permit(:code, :kind, :amount, :max_uses))
    end
  end
end

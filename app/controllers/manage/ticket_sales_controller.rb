# frozen_string_literal: true

module Manage
  class TicketSalesController < Manage::ManageController
    def index
      @productions = ticketing_enabled_productions

      # Overall sales stats
      @total_sales = organization_sales.count
      @total_revenue = organization_sales.sum(:total_cents)
      @recent_sales = organization_sales.recent.limit(20)

      # Sales by provider
      @sales_by_provider = TicketSale
        .joins(ticket_offer: { ticket_listing: :ticketing_provider })
        .where(ticketing_providers: { organization_id: Current.organization.id })
        .status_confirmed
        .group("ticketing_providers.name")
        .sum(:total_cents)
    end

    def production
      @production = Current.user.accessible_productions.find(params[:production_id])
      ensure_ticketing_enabled!
      @shows = @production.shows.upcoming.order(:date_and_time)

      # Production-level stats
      @total_sales = production_sales(@production).count
      @total_revenue = production_sales(@production).sum(:total_cents)
      @recent_sales = production_sales(@production).recent.limit(20)

      # Sales by show
      @sales_by_show = TicketSale
        .joins(ticket_offer: { ticket_listing: { show_ticketing: :show } })
        .where(shows: { production_id: @production.id })
        .status_confirmed
        .group("shows.id")
        .sum(:total_cents)
    end

    def show
      @production = Current.user.accessible_productions.find(params[:production_id])
      @show = @production.shows.find(params[:show_id])
      @show_ticketing = @show.show_ticketing

      if @show_ticketing
        @sales = show_sales(@show_ticketing).recent
        @total_revenue = show_sales(@show_ticketing).sum(:total_cents)
        @total_seats = show_sales(@show_ticketing).sum(:total_seats)

        # Sales by tier
        @sales_by_tier = TicketSale
          .joins(:show_ticket_tier)
          .where(show_ticket_tier_id: @show_ticketing.show_ticket_tiers.pluck(:id))
          .status_confirmed
          .group("show_ticket_tiers.name")
          .select("show_ticket_tiers.name, SUM(ticket_sales.total_cents) as revenue, SUM(ticket_sales.total_seats) as seats")
      else
        @sales = TicketSale.none
        @total_revenue = 0
        @total_seats = 0
        @sales_by_tier = []
      end
    end

    private

    def ticketing_enabled_productions
      Current.user.accessible_productions
        .includes(:contract)
        .order(:name)
        .select(&:ticketing_enabled?)
    end

    def ensure_ticketing_enabled!
      unless @production.ticketing_enabled?
        redirect_to manage_ticket_sales_path, alert: "Ticketing is not enabled for this production."
      end
    end

    def organization_sales
      TicketSale
        .joins(ticket_offer: { ticket_listing: { show_ticketing: { show: :production } } })
        .where(productions: { organization_id: Current.organization.id })
        .status_confirmed
    end

    def production_sales(production)
      TicketSale
        .joins(ticket_offer: { ticket_listing: { show_ticketing: :show } })
        .where(shows: { production_id: production.id })
        .status_confirmed
    end

    def show_sales(show_ticketing)
      TicketSale
        .joins(ticket_offer: :ticket_listing)
        .where(ticket_listings: { show_ticketing_id: show_ticketing.id })
        .status_confirmed
    end
  end
end

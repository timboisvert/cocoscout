# frozen_string_literal: true

module Manage
  class TicketingProductionsController < Manage::ManageController
    before_action :set_production

    def show
      @links = @production.ticketing_production_links
        .includes(:ticketing_provider, :ticketing_show_links)
        .order(created_at: :desc)

      @available_providers = Current.organization.ticketing_providers.enabled

      # Calculate summary stats
      @stats = build_stats

      # Get shows that could be linked but aren't
      linked_show_ids = TicketingShowLink
        .joins(:ticketing_production_link)
        .where(ticketing_production_links: { production_id: @production.id })
        .pluck(:show_id)

      @unlinked_shows = @production.shows
        .where("date_and_time >= ?", 30.days.ago)
        .where.not(id: linked_show_ids)
        .order(:date_and_time)
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def build_stats
      show_links = TicketingShowLink
        .joins(:ticketing_production_link)
        .where(ticketing_production_links: { production_id: @production.id })

      {
        total_links: @links.count,
        linked_shows: show_links.count,
        tickets_sold: show_links.sum(:tickets_sold),
        gross_revenue: show_links.sum(:gross_revenue),
        net_revenue: show_links.sum(:net_revenue),
        last_sync: @links.maximum(:last_synced_at)
      }
    end
  end
end

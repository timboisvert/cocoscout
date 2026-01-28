# frozen_string_literal: true

module Manage
  class TicketingController < Manage::ManageController
    def index
      @providers = Current.organization.ticketing_providers.order(:name)

      # Get all productions with their ticketing status
      @productions = Current.organization.productions.order(:name)

      # Build summary for each production
      @production_summaries = @productions.map do |production|
        build_production_summary(production)
      end

      # Pending events needing attention
      @pending_events_count = TicketingPendingEvent
        .joins(:ticketing_provider)
        .where(ticketing_providers: { organization_id: Current.organization.id })
        .pending
        .count

      # Organization-wide stats
      @org_stats = build_org_stats
    end

    private

    def build_production_summary(production)
      links = production.ticketing_production_links.includes(:ticketing_provider, :ticketing_show_links)

      # Calculate stats from all links for this production
      total_tickets_sold = 0
      total_revenue = 0
      linked_shows_count = 0
      sync_issues = 0

      links.each do |link|
        link.ticketing_show_links.each do |show_link|
          total_tickets_sold += show_link.tickets_sold.to_i
          total_revenue += show_link.net_revenue.to_f
          linked_shows_count += 1
          sync_issues += 1 if show_link.sync_status == "error"
        end
      end

      unlinked_shows_count = production.shows
        .where("date_and_time >= ?", 30.days.ago)
        .count - linked_shows_count

      {
        production: production,
        links_count: links.count,
        linked_shows: linked_shows_count,
        unlinked_shows: unlinked_shows_count,
        tickets_sold: total_tickets_sold,
        revenue: total_revenue,
        sync_issues: sync_issues,
        has_ticketing: links.any?,
        providers: links.map { |l| l.ticketing_provider.name }.uniq
      }
    end

    def build_org_stats
      show_links = TicketingShowLink
        .joins(ticketing_production_link: :ticketing_provider)
        .where(ticketing_providers: { organization_id: Current.organization.id })

      {
        total_providers: @providers.count,
        total_productions_linked: @production_summaries.count { |s| s[:has_ticketing] },
        total_tickets_synced: show_links.sum(:tickets_sold),
        total_revenue_synced: show_links.sum(:net_revenue),
        pending_events: @pending_events_count
      }
    end
  end
end

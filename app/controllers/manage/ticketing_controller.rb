# frozen_string_literal: true

module Manage
  class TicketingController < Manage::ManageController
    def index
      # Use the new dashboard service for issue-focused data
      @dashboard = TicketingDashboardService.new(Current.organization)
      @dashboard_data = @dashboard.dashboard_data

      # Get ticketing providers with sync status
      @providers = Current.organization.ticketing_providers.order(:name)

      # Get shows with ticketing set up (active ticketing only)
      production_ids = ticketing_enabled_productions.pluck(:id)
      @show_ticketings = ShowTicketing
        .joins(show: :production)
        .includes(show: [ :production, :location ], show_ticket_tiers: [], ticket_listings: :ticketing_provider)
        .where(shows: { production_id: production_ids })
        .where(shows: { canceled: false })
        .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
        .order("shows.date_and_time ASC")

      # Get linked events from providers (monitor-only mode)
      @linked_events = RemoteTicketingEvent
        .includes(:ticketing_provider, :show)
        .where(organization: Current.organization)
        .where.not(show_id: nil)
        .where(remote_status: %w[live published])
        .joins(:show)
        .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
        .order("shows.date_and_time ASC")

      # Build performance data for each show
      @show_performance = build_show_performance(@show_ticketings)

      # Calculate aggregate metrics (includes ShowTicketing AND linked events)
      @metrics = calculate_aggregate_metrics(@show_ticketings, @linked_events)

      # Issue counts for display
      # Include shows with ShowTicketing but missing proper provider listings
      shows_missing_listings = @show_ticketings.select { |st| st.ticket_listings.empty? }.count

      @issue_counts = {
        total: @dashboard.total_issue_count + shows_missing_listings,
        missing_listings: @dashboard_data[:issues][:missing_listings].count + shows_missing_listings,
        sync_failed: @dashboard_data[:issues][:sync_failed].count,
        auth_expired: @dashboard_data[:issues][:auth_expired].count,
        setup_incomplete: @dashboard_data[:issues][:setup_incomplete].count
      }
    end

    # Create missing listings for all shows
    def create_missing_listings
      dashboard = TicketingDashboardService.new(Current.organization)
      result = dashboard.create_missing_listings!

      if result[:errors].any?
        redirect_to manage_ticketing_index_path,
          alert: "Created #{result[:created].count} listings with #{result[:errors].count} errors."
      else
        redirect_to manage_ticketing_index_path,
          notice: "Created #{result[:created].count} listings."
      end
    end

    # Sync all ready listings
    def sync_all
      dashboard = TicketingDashboardService.new(Current.organization)
      dashboard.sync_all_ready!

      redirect_to manage_ticketing_index_path,
        notice: "Sync queued for all ready listings."
    end

    private

    # Get productions that have ticketing enabled
    def ticketing_enabled_productions
      Current.user.accessible_productions
        .includes(:contract)
        .order(:name)
        .select(&:ticketing_enabled?)
    end

    def build_show_performance(show_ticketings)
      show_ticketing_ids = show_ticketings.pluck(:id)

      # Get revenue per show_ticketing from confirmed sales
      revenue_by_ticketing = TicketSale
        .joins(ticket_offer: { ticket_listing: :show_ticketing })
        .where(show_ticketings: { id: show_ticketing_ids })
        .status_confirmed
        .group("show_ticketings.id")
        .sum(:total_cents)

      # Get sales count per show_ticketing
      sales_count_by_ticketing = TicketSale
        .joins(ticket_offer: { ticket_listing: :show_ticketing })
        .where(show_ticketings: { id: show_ticketing_ids })
        .status_confirmed
        .group("show_ticketings.id")
        .count

      show_ticketings.index_with do |ticketing|
        {
          capacity: ticketing.total_capacity,
          sold: ticketing.total_sold,
          available: ticketing.total_available,
          sold_percentage: ticketing.sold_percentage,
          revenue_cents: revenue_by_ticketing[ticketing.id] || 0,
          sales_count: sales_count_by_ticketing[ticketing.id] || 0
        }
      end
    end

    def calculate_aggregate_metrics(show_ticketings, linked_events)
      show_ticketing_ids = show_ticketings.pluck(:id)

      # Tier aggregates from ShowTicketing
      tier_stats = ShowTicketTier.where(show_ticketing_id: show_ticketing_ids)
      ticketing_capacity = tier_stats.sum(:capacity)
      ticketing_sold = tier_stats.sum(:sold)

      # Revenue from confirmed sales (ShowTicketing flow)
      ticketing_revenue = TicketSale
        .joins(ticket_offer: { ticket_listing: :show_ticketing })
        .where(show_ticketings: { id: show_ticketing_ids })
        .status_confirmed
        .sum(:total_cents)

      # Add data from linked events (monitor-only mode)
      linked_capacity = linked_events.sum(:capacity)
      linked_sold = linked_events.sum(:tickets_sold)
      linked_revenue = linked_events.sum(:revenue_cents)

      # Combine totals
      total_capacity = ticketing_capacity + linked_capacity
      total_sold = ticketing_sold + linked_sold
      total_revenue = ticketing_revenue + linked_revenue

      # Recent sales (last 7 days) - from ShowTicketing flow
      recent_sales = TicketSale
        .joins(ticket_offer: { ticket_listing: :show_ticketing })
        .where(show_ticketings: { id: show_ticketing_ids })
        .where(purchased_at: 7.days.ago..)
        .status_confirmed

      recent_revenue = recent_sales.sum(:total_cents)
      recent_count = recent_sales.count

      {
        total_capacity: total_capacity,
        total_sold: total_sold,
        total_available: total_capacity - total_sold,
        sell_through_percentage: total_capacity.positive? ? (total_sold.to_f / total_capacity * 100).round(1) : 0,
        total_revenue_cents: total_revenue,
        shows_count: show_ticketings.count + linked_events.count,
        linked_events_count: linked_events.count,
        recent_sales_count: recent_count,
        recent_revenue_cents: recent_revenue
      }
    end
  end
end

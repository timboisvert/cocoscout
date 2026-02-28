# frozen_string_literal: true

# Background job that pulls sales data from linked ticketing provider events
# Runs periodically to keep sales data up-to-date
class TicketingSalesSyncJob < ApplicationJob
  queue_as :default

  # Sync a single remote event's sales data
  def perform(remote_event_id = nil)
    if remote_event_id
      sync_single_event(remote_event_id)
    else
      sync_all_events
    end
  end

  private

  def sync_single_event(remote_event_id)
    event = RemoteTicketingEvent.find_by(id: remote_event_id)
    return unless event

    pull_sales_for_event(event)
  end

  def sync_all_events
    Rails.logger.info "[TicketingSalesSyncJob] Starting sales sync for all linked events"

    count = 0
    errors = 0

    # Get all remote events that are linked to shows and have live status
    RemoteTicketingEvent.includes(:ticketing_provider, :show)
                        .where.not(show_id: nil)
                        .where(remote_status: %w[live published])
                        .find_each do |event|
      # Skip if recently synced (within last 5 minutes)
      next if event.last_sales_synced_at && event.last_sales_synced_at > 5.minutes.ago

      # Skip if provider is rate limited
      next if event.ticketing_provider.rate_limited?

      result = pull_sales_for_event(event)
      if result[:success]
        count += 1
      else
        errors += 1
      end
    end

    Rails.logger.info "[TicketingSalesSyncJob] Completed: #{count} synced, #{errors} errors"
  end

  def pull_sales_for_event(event)
    provider = event.ticketing_provider
    return { success: false, error: "Provider not configured" } unless provider.configured?

    adapter = provider.adapter
    result = adapter.fetch_event_sales(event.external_event_id)

    unless result[:success]
      Rails.logger.warn "[TicketingSalesSyncJob] Failed to fetch sales for #{event.id}: #{result[:error]}"
      return result
    end

    event.update_sales_data!(
      sold: result[:tickets_sold],
      available: result[:tickets_available],
      capacity: result[:capacity],
      revenue_cents: result[:revenue_cents],
      currency: result[:currency] || "USD"
    )

    { success: true }
  rescue TicketingAdapters::RateLimitError => e
    provider.record_rate_limit!(resets_at: e.resets_at)
    { success: false, error: "Rate limited" }
  rescue TicketingAdapters::AuthenticationError => e
    provider.mark_credentials_invalid!(e.message)
    { success: false, error: "Authentication error" }
  rescue StandardError => e
    Rails.logger.error "[TicketingSalesSyncJob] Error syncing #{event.id}: #{e.message}"
    { success: false, error: e.message }
  end
end

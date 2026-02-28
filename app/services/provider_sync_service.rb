# frozen_string_literal: true

# ProviderSyncService fetches events from a ticketing provider and builds
# the provider-side data model:
#
#   ProviderEvent (series/parent) -> RemoteTicketingEvent (occurrences)
#
# This allows us to understand the provider's complete event structure before
# attempting to match with CocoScout productions/shows.
#
class ProviderSyncService
  attr_reader :provider, :adapter, :stats

  def initialize(provider)
    @provider = provider
    @adapter = provider.adapter
    @stats = { events_created: 0, events_updated: 0, occurrences_created: 0, occurrences_updated: 0, errors: [] }
  end

  def sync!
    Rails.logger.info "[ProviderSync] Starting sync for #{provider.name} (#{provider.provider_type})"

    result = adapter.list_events
    unless result[:success]
      stats[:errors] << result[:error]
      Rails.logger.error "[ProviderSync] Failed to fetch events: #{result[:error]}"
      return stats
    end

    raw_events = result[:events] || []
    Rails.logger.info "[ProviderSync] Fetched #{raw_events.count} events from provider"

    # Group events by series (handles different provider patterns)
    grouped = group_events_by_series(raw_events)
    Rails.logger.info "[ProviderSync] Grouped into #{grouped.count} event series"

    # Process each event series
    grouped.each do |series_key, occurrences|
      process_event_series(series_key, occurrences)
    end

    # Mark last sync time on provider
    provider.update!(last_sync_at: Time.current) if provider.respond_to?(:last_sync_at=)

    Rails.logger.info "[ProviderSync] Complete: #{stats}"
    stats
  end

  private

  # Group raw events into series
  # Different providers may structure this differently:
  # - Ticket Tailor: Each occurrence is a separate event, group by event_series_id or by name
  # - Eventbrite: Events have multiple occurrences as child objects
  def group_events_by_series(raw_events)
    grouped = {}

    raw_events.each do |event|
      # Try to find a series identifier
      series_key = extract_series_key(event)

      grouped[series_key] ||= []
      grouped[series_key] << event
    end

    grouped
  end

  # Extract a key to group related events/occurrences
  def extract_series_key(event)
    # Priority order:
    # 1. Explicit event_series_id field
    # 2. Base event ID (strip occurrence suffix like "ev_123:occ_456" -> "ev_123")
    # 3. Event name (fallback for providers without series concept)

    if event[:event_series_id].present?
      return "series:#{event[:event_series_id]}"
    end

    # For IDs like "ev_123:occ_456", extract base event ID
    event_id = event[:id].to_s
    if event_id.include?(":")
      base_id = event_id.split(":").first
      return "id:#{base_id}"
    end

    # Fallback: group by event name
    "name:#{event[:name]}"
  end

  def process_event_series(series_key, occurrences)
    return if occurrences.empty?

    # Use first occurrence's data for the series-level info
    first = occurrences.first
    external_event_id = extract_external_event_id(series_key, first)

    # Find or create the ProviderEvent
    provider_event = provider.provider_events.find_by(external_event_id: external_event_id)

    if provider_event
      update_provider_event(provider_event, first, occurrences)
      stats[:events_updated] += 1
    else
      provider_event = create_provider_event(external_event_id, first, occurrences, series_key)
      stats[:events_created] += 1
    end

    # Process each occurrence as a RemoteTicketingEvent
    occurrences.each do |occ|
      process_occurrence(provider_event, occ)
    end

    # Try to suggest a production match if unmapped
    provider_event.suggest_production_match! if provider_event.match_status_unmatched?
  rescue => e
    stats[:errors] << "Error processing #{series_key}: #{e.message}"
    Rails.logger.error "[ProviderSync] Error processing #{series_key}: #{e.message}"
  end

  def extract_external_event_id(series_key, first_event)
    case series_key
    when /^series:/
      series_key.sub("series:", "")
    when /^id:/
      series_key.sub("id:", "")
    else
      # For name-based grouping, use the first event's ID
      first_event[:id].to_s.split(":").first
    end
  end

  def create_provider_event(external_event_id, first_occ, occurrences, series_key)
    provider.provider_events.create!(
      organization: provider.organization,
      external_event_id: external_event_id,
      external_series_id: series_key.start_with?("series:") ? series_key.sub("series:", "") : nil,
      name: first_occ[:name],
      description: first_occ[:description],
      venue_name: first_occ[:venue_name] || first_occ.dig(:venue, :name),
      status: normalize_status(first_occ[:status]),
      match_status: :unmatched,
      last_synced_at: Time.current,
      raw_data: { first_occurrence: first_occ, occurrence_count: occurrences.size }
    )
  end

  def update_provider_event(provider_event, first_occ, occurrences)
    provider_event.update!(
      name: first_occ[:name],
      venue_name: first_occ[:venue_name] || first_occ.dig(:venue, :name),
      status: normalize_status(first_occ[:status]),
      last_synced_at: Time.current,
      raw_data: { first_occurrence: first_occ, occurrence_count: occurrences.size }
    )
  end

  def process_occurrence(provider_event, occurrence)
    external_event_id = occurrence[:id].to_s

    remote_event = RemoteTicketingEvent.find_by(
      ticketing_provider: provider,
      external_event_id: external_event_id
    )

    if remote_event
      update_remote_event(remote_event, occurrence)
      stats[:occurrences_updated] += 1
    else
      create_remote_event(provider_event, occurrence)
      stats[:occurrences_created] += 1
    end
  end

  def create_remote_event(provider_event, occurrence)
    RemoteTicketingEvent.create!(
      provider_event: provider_event,
      ticketing_provider: provider,
      organization: provider.organization,
      external_event_id: occurrence[:id].to_s,
      event_name: occurrence[:name],
      event_date: occurrence[:start_date] || occurrence[:start],
      venue_name: occurrence[:venue_name] || occurrence.dig(:venue, :name),
      tickets_sold: occurrence[:tickets_sold].to_i,
      tickets_available: occurrence[:tickets_available].to_i,
      capacity: occurrence[:capacity].to_i,
      revenue_cents: occurrence[:revenue_cents].to_i,
      sync_status: :synced,
      remote_status: normalize_remote_status(occurrence[:status]),
      external_url: occurrence[:external_url] || occurrence[:url],
      last_synced_at: Time.current,
      raw_data: occurrence
    )
  end

  def update_remote_event(remote_event, occurrence)
    remote_event.update!(
      event_name: occurrence[:name],
      event_date: occurrence[:start_date] || occurrence[:start],
      venue_name: occurrence[:venue_name] || occurrence.dig(:venue, :name),
      tickets_sold: occurrence[:tickets_sold].to_i,
      tickets_available: occurrence[:tickets_available].to_i,
      capacity: occurrence[:capacity].to_i,
      revenue_cents: occurrence[:revenue_cents].to_i,
      external_url: occurrence[:external_url] || occurrence[:url],
      last_synced_at: Time.current,
      raw_data: occurrence
    )
  end

  def normalize_status(status)
    case status&.downcase
    when "draft", "pending"
      :active
    when "live", "published", "active"
      :active
    when "completed", "ended", "past"
      :completed
    when "canceled", "cancelled", "deleted"
      :canceled
    else
      :active
    end
  end

  def normalize_remote_status(status)
    case status&.downcase
    when "draft"
      :draft
    when "live", "published", "on_sale"
      :live
    when "completed", "ended", "closed"
      :sales_closed
    when "canceled", "cancelled"
      :canceled
    when "sold_out"
      :sold_out
    else
      :draft
    end
  end
end

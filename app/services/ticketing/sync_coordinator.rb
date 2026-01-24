# frozen_string_literal: true

module Ticketing
  class SyncCoordinator
    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # Run a full sync for all linked productions
    def sync_all(user: nil)
      return { success: false, error: "Provider not healthy" } unless provider.healthy?
      return { success: false, error: "No credentials" } unless provider.has_credentials?

      results = {
        success: true,
        productions_synced: 0,
        total_updated: 0,
        total_failed: 0,
        errors: []
      }

      provider.ticketing_production_links.enabled.find_each do |link|
        result = sync_production(link, user: user)

        if result[:success]
          results[:productions_synced] += 1
          results[:total_updated] += result[:records_updated] || 0
        else
          results[:errors] << "#{link.production.name}: #{result[:error]}"
          results[:total_failed] += 1
        end
      end

      results[:success] = results[:errors].empty?
      results
    end

    # Sync a specific production
    def sync_production(production_link, user: nil)
      return { success: false, error: "Sync not enabled" } unless production_link.sync_enabled?

      Operations::ImportSales.new(production_link, user: user).call
    end

    # Test the provider connection
    def test_connection
      service = provider.service

      # Try to fetch events to verify credentials work
      response = service.fetch_events
      event_count = extract_event_count(response)

      {
        success: true,
        message: "Connected successfully",
        event_count: event_count,
        account_name: extract_account_name(response)
      }
    rescue Ticketing::BaseService::AuthenticationError => e
      { success: false, error: "Authentication failed: #{e.message}" }
    rescue Ticketing::BaseService::ApiError => e
      { success: false, error: "API error: #{e.message}" }
    rescue => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    # Fetch available events from the provider for linking
    def fetch_available_events
      service = provider.service
      response = service.fetch_events

      normalize_events(response)
    rescue => e
      Rails.logger.error("Failed to fetch events: #{e.message}")
      []
    end

    private

    def extract_event_count(response)
      case provider.provider_type
      when "ticket_tailor"
        response["data"]&.size || 0
      when "eventbrite"
        response["events"]&.size || response.dig("pagination", "object_count") || 0
      else
        response["data"]&.size || response["events"]&.size || 0
      end
    end

    def extract_account_name(response)
      case provider.provider_type
      when "ticket_tailor"
        # Ticket Tailor doesn't return account name in events response
        nil
      when "eventbrite"
        response.dig("organizer", "name")
      else
        nil
      end
    end

    def normalize_events(response)
      events = case provider.provider_type
      when "ticket_tailor"
        response["data"] || []
      when "eventbrite"
        response["events"] || []
      else
        response["data"] || response["events"] || []
      end

      events.map { |e| normalize_event(e) }
    end

    def normalize_event(event)
      case provider.provider_type
      when "ticket_tailor"
        {
          id: event["id"],
          name: event["name"],
          status: event["status"],
          url: event["url"],
          occurrence_count: event["events_count"] || event.dig("events", "total"),
          created_at: event["created_at"]
        }
      when "eventbrite"
        {
          id: event["id"],
          name: event.dig("name", "text") || event["name"],
          status: event["status"],
          url: event["url"],
          occurrence_count: 1,  # Eventbrite doesn't have series by default
          created_at: event["created"]
        }
      else
        {
          id: event["id"],
          name: event["name"] || event["title"],
          status: event["status"],
          url: event["url"],
          occurrence_count: event["occurrence_count"],
          created_at: event["created_at"]
        }
      end
    end
  end
end

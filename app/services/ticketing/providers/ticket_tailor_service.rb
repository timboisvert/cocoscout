# frozen_string_literal: true

module Ticketing
  module Providers
    class TicketTailorService < Ticketing::BaseService
      BASE_URL = "https://api.tickettailor.com/v1"

      def capabilities
        {
          read_events: true,
          read_sales: true,
          read_pricing: true,
          write_events: true,  # Available but not implemented yet
          webhooks: true
        }
      end

      # === Authentication ===
      # Ticket Tailor uses API key authentication (Basic Auth with key as username)

      def apply_api_key(request)
        request.basic_auth(provider.api_key, "")
      end

      # === Read Operations ===

      def fetch_events(since: nil)
        # Ticket Tailor calls these "event_series"
        http_get("#{BASE_URL}/event_series")
      end

      def fetch_event(provider_event_id)
        http_get("#{BASE_URL}/event_series/#{provider_event_id}")
      end

      def fetch_occurrences(provider_event_id)
        # Individual events within a series
        http_get("#{BASE_URL}/event_series/#{provider_event_id}/events")
      end

      def fetch_sales(provider_event_id, occurrence_id: nil, since: nil)
        path = if occurrence_id.present?
          "#{BASE_URL}/events/#{occurrence_id}/issued_tickets"
        else
          "#{BASE_URL}/event_series/#{provider_event_id}/issued_tickets"
        end

        http_get(path)
      end

      def fetch_ticket_types(provider_event_id)
        http_get("#{BASE_URL}/event_series/#{provider_event_id}/ticket_types")
      end

      # === URL Generation ===

      def dashboard_url
        "https://www.tickettailor.com/box-office"
      end

      def event_dashboard_url(provider_event_id)
        "https://www.tickettailor.com/box-office/events/series/#{provider_event_id}"
      end

      def ticket_page_url_for(show_link)
        occurrence_id = show_link.provider_occurrence_id
        return nil unless occurrence_id.present?

        # Ticket Tailor event URLs follow this pattern
        # The actual URL structure depends on the box office subdomain
        "https://www.tickettailor.com/events/#{occurrence_id}"
      end

      # === Data Normalization ===

      def normalize_event_series(data)
        {
          id: data["id"],
          name: data["name"],
          description: data["description"],
          status: data["status"],
          url: data["url"],
          created_at: parse_timestamp(data["created_at"]),
          updated_at: parse_timestamp(data["updated_at"])
        }
      end

      def normalize_occurrence(data)
        {
          id: data["id"],
          event_series_id: data["event_series_id"],
          start_at: parse_timestamp(data["start"]),
          end_at: parse_timestamp(data["end"]),
          status: data["status"],
          tickets_available: data["tickets_available"],
          tickets_issued: data["tickets_issued"],
          url: data["url"]
        }
      end

      def normalize_ticket(data)
        {
          id: data["id"],
          event_id: data["event_id"],
          ticket_type_id: data["ticket_type_id"],
          ticket_type_name: data.dig("ticket_type", "name"),
          price: cents_to_dollars(data["price"]),
          status: data["status"],
          created_at: parse_timestamp(data["created_at"])
        }
      end

      private

      def parse_timestamp(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def cents_to_dollars(cents)
        return 0 if cents.blank?

        cents.to_f / 100
      end
    end
  end
end

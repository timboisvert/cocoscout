# frozen_string_literal: true

module Ticketing
  module Operations
    class ImportSales
      attr_reader :production_link, :provider, :service, :sync_log

      def initialize(production_link, user: nil)
        @production_link = production_link
        @provider = production_link.ticketing_provider
        @service = provider.service
        @user = user
      end

      def call
        return { success: false, error: "Sync not enabled" } unless production_link.sync_enabled?

        @sync_log = TicketingSyncLog.start!(
          ticketing_provider: provider,
          production_link: production_link,
          user: @user,
          sync_type: @user ? "manual" : "incremental"
        )

        begin
          import_all_show_sales
          sync_log.mark_success!
          provider.mark_sync_success!

          {
            success: true,
            records_updated: sync_log.records_updated,
            records_failed: sync_log.records_failed
          }
        rescue Ticketing::BaseService::AuthenticationError => e
          handle_error(e, "Authentication failed")
        rescue Ticketing::BaseService::RateLimitError => e
          handle_error(e, "Rate limited by provider")
        rescue Ticketing::BaseService::ApiError => e
          handle_error(e, "API error")
        rescue => e
          handle_error(e, "Unexpected error")
        end
      end

      private

      def import_all_show_sales
        production_link.ticketing_show_links.find_each do |show_link|
          import_show_sales(show_link)
        end
      end

      def import_show_sales(show_link)
        return unless show_link.provider_occurrence_id.present?

        # Only sync recent/upcoming shows
        return if show_link.show.date_and_time < 30.days.ago

        sales_data = fetch_sales_data(show_link)
        processed = process_sales_data(sales_data, show_link)

        show_link.update!(
          tickets_sold: processed[:tickets_sold],
          tickets_available: processed[:tickets_available],
          tickets_capacity: processed[:tickets_capacity],
          gross_revenue: processed[:gross_revenue],
          net_revenue: processed[:net_revenue],
          ticket_breakdown: processed[:breakdown],
          last_synced_at: Time.current,
          sync_status: "synced"
        )

        sync_log.increment_updated!
      rescue => e
        Rails.logger.error("Failed to sync show #{show_link.show_id}: #{e.message}")
        show_link.mark_error!(e.message)
        sync_log.increment_failed!
      end

      def fetch_sales_data(show_link)
        service.fetch_sales(
          production_link.provider_event_id,
          occurrence_id: show_link.provider_occurrence_id,
          since: show_link.last_synced_at
        )
      end

      def process_sales_data(data, show_link)
        # Provider-specific normalization
        case provider.provider_type
        when "ticket_tailor"
          process_ticket_tailor_sales(data, show_link)
        when "eventbrite"
          process_eventbrite_sales(data, show_link)
        else
          process_generic_sales(data, show_link)
        end
      end

      def process_ticket_tailor_sales(data, show_link)
        # Ticket Tailor returns issued_tickets with pagination
        tickets = data["data"] || []

        # Group by ticket type
        by_type = tickets.group_by { |t| t.dig("ticket_type", "id") }

        breakdown = by_type.map do |type_id, type_tickets|
          first_ticket = type_tickets.first
          ticket_type = first_ticket["ticket_type"] || {}

          # Ticket Tailor prices are in cents
          price_cents = first_ticket["price"].to_i
          fees_cents = first_ticket.dig("buyer_fee", "total").to_i

          {
            "id" => type_id,
            "name" => ticket_type["name"] || "Ticket",
            "quantity" => type_tickets.size,
            "price" => price_cents / 100.0,
            "subtotal" => (price_cents * type_tickets.size) / 100.0,
            "fee_per_ticket" => fees_cents / 100.0,
            "fees" => (fees_cents * type_tickets.size) / 100.0
          }
        end

        total_sold = tickets.size
        gross = breakdown.sum { |b| b["subtotal"] }
        fees = breakdown.sum { |b| b["fees"] }

        # Try to get capacity from occurrence data
        capacity = nil
        available = nil
        if show_link.provider_occurrence_id
          begin
            occurrence = service.http_get(
              "https://api.tickettailor.com/v1/events/#{show_link.provider_occurrence_id}"
            )
            capacity = occurrence["tickets_available"].to_i + occurrence["tickets_issued"].to_i
            available = occurrence["tickets_available"].to_i
          rescue => e
            Rails.logger.debug("Could not fetch occurrence capacity: #{e.message}")
          end
        end

        {
          tickets_sold: total_sold,
          tickets_available: available,
          tickets_capacity: capacity,
          gross_revenue: gross,
          net_revenue: gross - fees,
          breakdown: breakdown
        }
      end

      def process_eventbrite_sales(data, show_link)
        # Eventbrite returns attendees with pagination
        attendees = data["attendees"] || []

        # Group by ticket class
        by_class = attendees.group_by { |a| a.dig("ticket_class_id") }

        breakdown = by_class.map do |class_id, class_attendees|
          first = class_attendees.first
          costs = first["costs"] || {}

          {
            "id" => class_id,
            "name" => first.dig("ticket_class_name") || "Ticket",
            "quantity" => class_attendees.size,
            "price" => (costs.dig("base_price", "value") || 0) / 100.0,
            "subtotal" => class_attendees.sum { |a| (a.dig("costs", "base_price", "value") || 0) } / 100.0,
            "fee_per_ticket" => (costs.dig("eventbrite_fee", "value") || 0) / 100.0,
            "fees" => class_attendees.sum { |a| (a.dig("costs", "eventbrite_fee", "value") || 0) } / 100.0
          }
        end

        total_sold = attendees.size
        gross = breakdown.sum { |b| b["subtotal"] }
        fees = breakdown.sum { |b| b["fees"] }

        {
          tickets_sold: total_sold,
          tickets_available: nil,
          tickets_capacity: nil,
          gross_revenue: gross,
          net_revenue: gross - fees,
          breakdown: breakdown
        }
      end

      def process_generic_sales(data, show_link)
        # Generic fallback for unknown providers
        {
          tickets_sold: data["total_sold"] || data["count"] || 0,
          tickets_available: data["available"],
          tickets_capacity: data["capacity"],
          gross_revenue: data["gross_revenue"] || data["total_revenue"] || 0,
          net_revenue: data["net_revenue"] || data["gross_revenue"] || 0,
          breakdown: []
        }
      end

      def handle_error(error, context)
        Rails.logger.error("#{context} for provider #{provider.id}: #{error.message}")

        sync_log.mark_failed!(error, backtrace: error.backtrace)
        provider.mark_sync_failure!(error)

        {
          success: false,
          error: "#{context}: #{error.message}"
        }
      end
    end
  end
end

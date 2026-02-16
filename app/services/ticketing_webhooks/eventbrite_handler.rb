# frozen_string_literal: true

module TicketingWebhooks
  class EventbriteHandler < BaseHandler
    protected

    def handle_sale(webhook_log, payload)
      # Eventbrite sends order.placed webhook
      order_data = fetch_order_details(payload)
      return { success: false, error: "Could not fetch order details" } unless order_data

      event_id = order_data["event_id"]
      listing = find_listing(event_id)

      unless listing
        return { success: true, ignored: true, reason: "No listing found for event #{event_id}" }
      end

      # Update the webhook_log with the listing
      webhook_log.update!(ticket_listing: listing)

      # Process each attendee as a sale
      sales_created = 0
      order_data["attendees"]&.each do |attendee|
        next unless attendee["status"] == "Attending"

        external_sale_id = attendee["id"]

        # Check for duplicate
        if find_existing_sale(external_sale_id)
          next
        end

        ticket_class_id = attendee["ticket_class_id"]
        offer = listing.ticket_offers.find_by(external_offer_id: ticket_class_id)
        next unless offer

        # Create the sale
        sale = offer.ticket_sales.create!(
          show_ticket_tier: offer.show_ticket_tier,
          external_sale_id: external_sale_id,
          quantity: 1,
          total_seats: offer.seats_per_offer,
          total_cents: attendee.dig("costs", "gross", "value") || 0,
          customer_name: "#{attendee.dig('profile', 'first_name')} #{attendee.dig('profile', 'last_name')}".strip,
          customer_email: attendee.dig("profile", "email"),
          purchased_at: Time.parse(order_data["created"]),
          synced_at: Time.current,
          status: :confirmed
        )

        # Update tier availability
        listing.show_ticketing.process_sale!(offer.show_ticket_tier_id, sale.total_seats)
        sales_created += 1
      end

      if sales_created > 0
        { success: true, message: "Created #{sales_created} sale(s)" }
      else
        { success: true, ignored: true, reason: "No new sales to process" }
      end
    end

    def handle_refund(webhook_log, payload)
      order_data = fetch_order_details(payload)
      return { success: false, error: "Could not fetch order details" } unless order_data

      refunds_processed = 0
      order_data["attendees"]&.each do |attendee|
        next unless attendee["refunded"]

        sale = find_existing_sale(attendee["id"])
        next unless sale
        next if sale.status_refunded?

        sale.update!(status: :refunded)

        # Restore inventory
        sale.show_ticket_tier.record_refund!(sale.total_seats)
        refunds_processed += 1
      end

      if refunds_processed > 0
        { success: true, message: "Processed #{refunds_processed} refund(s)" }
      else
        { success: true, ignored: true, reason: "No refunds to process" }
      end
    end

    def handle_event_update(webhook_log, payload)
      event_id = extract_event_id(payload)
      listing = find_listing(event_id)

      unless listing
        return { success: true, ignored: true, reason: "No listing found for event #{event_id}" }
      end

      webhook_log.update!(ticket_listing: listing)

      # Mark listing for review - external changes detected
      listing.update!(
        external_last_modified_at: Time.current,
        sync_errors: listing.sync_errors + [{
          message: "External event updated - review for sync",
          at: Time.current.iso8601
        }]
      )

      { success: true, message: "Marked listing for review" }
    end

    def handle_event_published(webhook_log, payload)
      event_id = extract_event_id(payload)
      listing = find_listing(event_id)

      unless listing
        return { success: true, ignored: true, reason: "No listing found for event #{event_id}" }
      end

      webhook_log.update!(ticket_listing: listing)

      if listing.status_pending_approval?
        listing.mark_approved!
        { success: true, message: "Listing approved and live" }
      else
        { success: true, ignored: true, reason: "Listing not pending approval" }
      end
    end

    def handle_event_cancelled(webhook_log, payload)
      event_id = extract_event_id(payload)
      listing = find_listing(event_id)

      unless listing
        return { success: true, ignored: true, reason: "No listing found for event #{event_id}" }
      end

      webhook_log.update!(ticket_listing: listing)

      listing.end_listing!
      { success: true, message: "Listing marked as ended" }
    end

    private

    def fetch_order_details(payload)
      # Eventbrite webhooks contain api_url to fetch full details
      api_url = payload["api_url"]
      return nil unless api_url

      # Use the adapter to fetch
      adapter = provider.adapter
      # Extract path from full URL
      path = api_url.sub("https://www.eventbriteapi.com/v3", "")
      response = adapter.send(:get, "#{path}?expand=attendees")

      response[:success] ? response[:data] : nil
    rescue StandardError => e
      log_error("Failed to fetch order details: #{e.message}")
      nil
    end

    def extract_event_id(payload)
      payload["api_url"]&.match(/events\/(\d+)/)&.captures&.first
    end
  end
end

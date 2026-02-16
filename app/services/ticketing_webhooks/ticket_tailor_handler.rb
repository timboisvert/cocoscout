# frozen_string_literal: true

module TicketingWebhooks
  class TicketTailorHandler < BaseHandler
    protected

    def handle_sale(webhook_log, payload)
      # Ticket Tailor sends order.completed webhook
      data = payload["data"] || {}
      event_id = data["event_id"]

      # Ticket Tailor may use compound IDs
      listing = find_listing_by_event(event_id)

      unless listing
        return { success: true, ignored: true, reason: "No listing found for event #{event_id}" }
      end

      webhook_log.update!(ticket_listing: listing)

      order_id = data["id"]
      external_sale_id = order_id

      # Check for duplicate
      if find_existing_sale(external_sale_id)
        return { success: true, duplicate: true }
      end

      # Process issued tickets
      sales_created = 0
      issued_tickets = data["issued_tickets"] || []

      issued_tickets.each do |ticket|
        ticket_type_id = ticket["ticket_type_id"]
        offer = listing.ticket_offers.find_by(external_offer_id: ticket_type_id)
        next unless offer

        sale_id = "#{order_id}-#{ticket['id']}"

        # Skip if this specific ticket already recorded
        next if find_existing_sale(sale_id)

        sale = offer.ticket_sales.create!(
          show_ticket_tier: offer.show_ticket_tier,
          external_sale_id: sale_id,
          quantity: 1,
          total_seats: offer.seats_per_offer,
          total_cents: ticket["price"].to_i,
          customer_name: data["buyer_name"],
          customer_email: data["buyer_email"],
          customer_phone: data["buyer_phone"],
          purchased_at: Time.parse(data["created_at"]),
          synced_at: Time.current,
          status: :confirmed
        )

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
      data = payload["data"] || {}
      order_id = data["order_id"] || data["id"]

      # Find all sales for this order
      sales = TicketSale.joins(ticket_offer: :ticket_listing)
                        .where(ticket_listings: { ticketing_provider_id: provider.id })
                        .where("external_sale_id LIKE ?", "#{order_id}%")

      refunds_processed = 0
      sales.each do |sale|
        next if sale.status_refunded?

        sale.update!(status: :refunded)
        sale.show_ticket_tier.record_refund!(sale.total_seats)
        refunds_processed += 1
      end

      if refunds_processed > 0
        { success: true, message: "Processed #{refunds_processed} refund(s)" }
      else
        { success: true, ignored: true, reason: "No refunds to process" }
      end
    end

    private

    def find_listing_by_event(event_id)
      return nil if event_id.blank?

      # Ticket Tailor uses compound IDs like "event_id:occurrence_id"
      provider.ticket_listings.find_by("external_event_id LIKE ?", "#{event_id}%")
    end
  end
end

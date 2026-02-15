# frozen_string_literal: true

module TicketingAdapters
  class EventbriteAdapter < BaseAdapter
    BASE_URL = "https://www.eventbriteapi.com/v3"

    def test_connection
      response = get("/users/me/")

      if response[:success]
        { success: true }
      else
        { success: false, error: response[:error] || "Connection failed" }
      end
    end

    def create_event(listing)
      show = listing.show_ticketing.show

      event_data = {
        event: {
          name: { html: show.display_name },
          description: { html: show.description || "" },
          start: { timezone: "America/New_York", utc: show.date_and_time.utc.iso8601 },
          end: { timezone: "America/New_York", utc: (show.end_time || show.date_and_time + 2.hours).utc.iso8601 },
          currency: "USD",
          online_event: show.online?,
          listed: true,
          shareable: true
        }
      }

      # Add venue if location exists
      if show.location.present? && !show.online?
        venue_id = find_or_create_venue(show.location)
        event_data[:event][:venue_id] = venue_id if venue_id
      end

      response = post("/organizations/#{organization_id}/events/", event_data)

      if response[:success]
        event_id = response[:data]["id"]
        event_url = response[:data]["url"]

        # Create ticket classes for each offer
        create_ticket_classes(listing, event_id)

        { success: true, event_id: event_id, event_url: event_url }
      else
        { success: false, error: response[:error] }
      end
    end

    def update_event(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      show = listing.show_ticketing.show

      event_data = {
        event: {
          name: { html: show.display_name },
          description: { html: show.description || "" },
          start: { timezone: "America/New_York", utc: show.date_and_time.utc.iso8601 },
          end: { timezone: "America/New_York", utc: (show.end_time || show.date_and_time + 2.hours).utc.iso8601 }
        }
      }

      response = post("/events/#{listing.external_event_id}/", event_data)

      if response[:success]
        { success: true }
      else
        { success: false, error: response[:error] }
      end
    end

    def update_inventory(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      # Update each ticket class quantity
      listing.ticket_offers.each do |offer|
        next unless offer.external_offer_id

        response = post("/events/#{listing.external_event_id}/ticket_classes/#{offer.external_offer_id}/", {
          ticket_class: {
            quantity_total: offer.quantity
          }
        })

        unless response[:success]
          return { success: false, error: "Failed to update offer #{offer.name}: #{response[:error]}" }
        end
      end

      { success: true }
    end

    def fetch_sales(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      sales = []
      continuation = nil

      loop do
        url = "/events/#{listing.external_event_id}/orders/"
        url += "?continuation=#{continuation}" if continuation

        response = get(url)

        unless response[:success]
          return { success: false, error: response[:error] }
        end

        orders = response[:data]["orders"] || []

        orders.each do |order|
          next unless order["status"] == "placed"

          order["attendees"]&.each do |attendee|
            ticket_class_id = attendee.dig("ticket_class_id")
            offer = listing.ticket_offers.find_by(external_offer_id: ticket_class_id)

            next unless offer

            sales << {
              sale_id: attendee["id"],
              offer_id: ticket_class_id,
              quantity: 1,
              total_cents: (attendee.dig("costs", "gross", "value") || 0),
              customer_name: "#{attendee.dig('profile', 'first_name')} #{attendee.dig('profile', 'last_name')}".strip,
              customer_email: attendee.dig("profile", "email"),
              purchased_at: Time.parse(order["created"])
            }
          end
        end

        continuation = response[:data].dig("pagination", "continuation")
        break unless continuation
      end

      { success: true, sales: sales }
    end

    def sync_listing(listing)
      # Pull latest sales
      result = fetch_sales(listing)
      return result unless result[:success]

      # Process sales is handled by the listing model
      { success: true }
    end

    private

    def organization_id
      settings["organization_id"] || fetch_organization_id
    end

    def fetch_organization_id
      response = get("/users/me/organizations/")
      return nil unless response[:success]

      orgs = response[:data]["organizations"] || []
      orgs.first&.dig("id")
    end

    def find_or_create_venue(location)
      # For now, return nil - venue creation requires address details
      # This can be expanded to create/find venues based on location data
      nil
    end

    def create_ticket_classes(listing, event_id)
      listing.ticket_offers.each do |offer|
        response = post("/events/#{event_id}/ticket_classes/", {
          ticket_class: {
            name: offer.name,
            description: offer.description,
            quantity_total: offer.quantity,
            cost: "USD,#{offer.price_cents}",
            free: offer.price_cents.zero?,
            minimum_quantity: 1,
            maximum_quantity: 10
          }
        })

        if response[:success]
          offer.update!(external_offer_id: response[:data]["id"])
        end
      end
    end

    def get(path)
      uri = URI("#{BASE_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error = JSON.parse(response.body).dig("error_description") rescue response.body
        { success: false, error: error }
      end
    rescue StandardError => e
      handle_error(e)
    end

    def post(path, data)
      uri = URI("#{BASE_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = data.to_json

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error = JSON.parse(response.body).dig("error_description") rescue response.body
        { success: false, error: error }
      end
    rescue StandardError => e
      handle_error(e)
    end
  end
end

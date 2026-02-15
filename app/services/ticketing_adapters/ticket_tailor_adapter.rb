# frozen_string_literal: true

module TicketingAdapters
  class TicketTailorAdapter < BaseAdapter
    BASE_URL = "https://api.tickettailor.com/v1"

    def test_connection
      response = get("/events")

      if response[:success]
        { success: true }
      else
        { success: false, error: response[:error] || "Connection failed" }
      end
    end

    def create_event(listing)
      show = listing.show_ticketing.show

      event_data = {
        name: show.display_name,
        description: show.description || "",
        url: nil, # Can be set if there's an event page
        currency: "usd",
        timezone: "America/New_York",
        venue: build_venue_data(show.location),
        online_event: show.online? ? "yes" : "no"
      }

      response = post("/events", event_data)

      unless response[:success]
        return { success: false, error: response[:error] }
      end

      event_id = response[:data]["id"]

      # Create event series/occurrence for the specific date
      occurrence_data = {
        event_id: event_id,
        start: show.date_and_time.iso8601,
        end: (show.end_time || show.date_and_time + 2.hours).iso8601
      }

      occurrence_response = post("/event_series", occurrence_data)

      unless occurrence_response[:success]
        return { success: false, error: occurrence_response[:error] }
      end

      occurrence_id = occurrence_response[:data]["id"]

      # Create ticket types for each offer
      create_ticket_types(listing, event_id)

      event_url = "https://www.tickettailor.com/events/#{settings['box_office_slug'] || 'event'}/#{event_id}"

      { success: true, event_id: "#{event_id}:#{occurrence_id}", event_url: event_url }
    end

    def update_event(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      event_id, occurrence_id = listing.external_event_id.split(":")
      show = listing.show_ticketing.show

      event_data = {
        name: show.display_name,
        description: show.description || ""
      }

      response = patch("/events/#{event_id}", event_data)

      if response[:success]
        # Update occurrence times
        if occurrence_id
          patch("/event_series/#{occurrence_id}", {
            start: show.date_and_time.iso8601,
            end: (show.end_time || show.date_and_time + 2.hours).iso8601
          })
        end

        { success: true }
      else
        { success: false, error: response[:error] }
      end
    end

    def update_inventory(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      event_id, _occurrence_id = listing.external_event_id.split(":")

      listing.ticket_offers.each do |offer|
        next unless offer.external_offer_id

        response = patch("/ticket_types/#{offer.external_offer_id}", {
          quantity: offer.quantity
        })

        unless response[:success]
          return { success: false, error: "Failed to update offer #{offer.name}: #{response[:error]}" }
        end
      end

      { success: true }
    end

    def fetch_sales(listing)
      return { success: false, error: "No external event ID" } unless listing.external_event_id

      event_id, _occurrence_id = listing.external_event_id.split(":")
      sales = []

      response = get("/orders?event_id=#{event_id}")

      unless response[:success]
        return { success: false, error: response[:error] }
      end

      orders = response[:data]["data"] || []

      orders.each do |order|
        next unless order["status"] == "completed"

        order["issued_tickets"]&.each do |ticket|
          ticket_type_id = ticket["ticket_type_id"]
          offer = listing.ticket_offers.find_by(external_offer_id: ticket_type_id)

          next unless offer

          sales << {
            sale_id: ticket["id"],
            offer_id: ticket_type_id,
            quantity: 1,
            total_cents: ticket["price"].to_i,
            customer_name: order["buyer_name"],
            customer_email: order["buyer_email"],
            customer_phone: order["buyer_phone"],
            purchased_at: Time.parse(order["created_at"])
          }
        end
      end

      { success: true, sales: sales }
    end

    def sync_listing(listing)
      fetch_sales(listing)
    end

    private

    def build_venue_data(location)
      return nil unless location

      {
        name: location.name,
        address_line_1: location.address_line1,
        address_line_2: location.address_line2,
        city: location.city,
        region: location.state,
        postal_code: location.postal_code,
        country: location.country || "US"
      }.compact
    end

    def create_ticket_types(listing, event_id)
      listing.ticket_offers.each do |offer|
        response = post("/ticket_types", {
          event_id: event_id,
          name: offer.name,
          description: offer.description,
          quantity: offer.quantity,
          price: offer.price_cents,
          min_per_order: 1,
          max_per_order: 10,
          status: "on_sale"
        })

        if response[:success]
          offer.update!(external_offer_id: response[:data]["id"])
        end
      end
    end

    def auth_header
      # Ticket Tailor uses Basic auth with API key as username
      Base64.strict_encode64("#{api_key}:")
    end

    def get(path)
      uri = URI("#{BASE_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Basic #{auth_header}"
      request["Accept"] = "application/json"

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error = JSON.parse(response.body).dig("message") rescue response.body
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
      request["Authorization"] = "Basic #{auth_header}"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Accept"] = "application/json"
      request.body = URI.encode_www_form(flatten_hash(data))

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error = JSON.parse(response.body).dig("message") rescue response.body
        { success: false, error: error }
      end
    rescue StandardError => e
      handle_error(e)
    end

    def patch(path, data)
      uri = URI("#{BASE_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Patch.new(uri)
      request["Authorization"] = "Basic #{auth_header}"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Accept"] = "application/json"
      request.body = URI.encode_www_form(flatten_hash(data))

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error = JSON.parse(response.body).dig("message") rescue response.body
        { success: false, error: error }
      end
    rescue StandardError => e
      handle_error(e)
    end

    def flatten_hash(hash, prefix = nil)
      hash.each_with_object({}) do |(key, value), result|
        new_key = prefix ? "#{prefix}[#{key}]" : key.to_s

        if value.is_a?(Hash)
          result.merge!(flatten_hash(value, new_key))
        else
          result[new_key] = value
        end
      end
    end
  end
end

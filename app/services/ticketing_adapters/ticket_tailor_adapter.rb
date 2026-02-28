# frozen_string_literal: true

module TicketingAdapters
  class TicketTailorAdapter < BaseAdapter
    BASE_URL = "https://api.tickettailor.com/v1"

    # Ticket Tailor capabilities
    CAPABILITIES = {
      "api_create_event" => true,
      "api_update_event" => true,
      "api_sync_inventory" => true,
      "api_fetch_sales" => true,
      "webhook_sales" => true,
      "webhook_inventory" => false,
      "webhook_event_updates" => false,
      "requires_approval" => false,
      "supports_draft" => true
    }.freeze

    # Required fields for Ticket Tailor listings
    def required_fields
      {
        show_name: ->(listing) { listing.show_ticketing.show.display_name.present? },
        show_date: ->(listing) { listing.show_ticketing.show.date_and_time.present? },
        ticket_tiers: ->(listing) { listing.show_ticketing.show_ticket_tiers.any? }
      }
    end

    # ============================================
    # Webhook Handling
    # ============================================

    def verify_webhook_signature(request)
      return { valid: false, error: "No webhook secret configured" } if provider.webhook_secret.blank?

      signature = request.headers["Ticket-Tailor-Signature"]
      return { valid: false, error: "Missing signature" } if signature.blank?

      # Ticket Tailor signature format: t=timestamp,v1=signature
      parts = signature.split(",").map { |p| p.split("=", 2) }.to_h
      timestamp = parts["t"]
      sig = parts["v1"]

      return { valid: false, error: "Invalid signature format" } if timestamp.blank? || sig.blank?

      # Verify timestamp is recent (within 5 minutes)
      if (Time.now.to_i - timestamp.to_i).abs > 300
        return { valid: false, error: "Timestamp too old" }
      end

      # Compute expected signature
      payload = "#{timestamp}.#{request.raw_post}"
      expected = OpenSSL::HMAC.hexdigest("SHA256", provider.webhook_secret, payload)

      if ActiveSupport::SecurityUtils.secure_compare(sig, expected)
        { valid: true }
      else
        { valid: false, error: "Invalid signature" }
      end
    end

    def parse_webhook(payload)
      {
        event_type: payload["event"] || "unknown",
        external_event_id: payload.dig("data", "event_id"),
        external_order_id: payload.dig("data", "order_id") || payload.dig("data", "id"),
        data: payload
      }
    end

    # ============================================
    # Core API Methods
    # ============================================

    def test_connection
      check_rate_limit!
      response = get("/events")

      if response[:success]
        { success: true }
      else
        { success: false, error: response[:error] || "Connection failed" }
      end
    end

    # Fetch all events from the provider
    def list_events
      check_rate_limit!
      events = []
      continuation = nil

      loop do
        url = "/events?limit=100"
        url += "&continuation=#{continuation}" if continuation

        response = get(url)
        unless response[:success]
          return { success: false, error: response[:error] }
        end

        data = response[:data]["data"] || []
        data.each do |event|
          # Ticket Tailor returns each occurrence as a separate event
          events << normalize_event(event, nil)
        end

        # Check for pagination
        continuation = response[:data].dig("links", "next")
        break if continuation.blank?
      end

      { success: true, events: events }
    end

    # Fetch sales data for a single event
    def fetch_event_sales(external_event_id)
      check_rate_limit!

      # Handle occurrence-based events (event_id:occurrence_id)
      event_id, occurrence_id = external_event_id.split(":")
      url = "/events/#{event_id}"
      url += "?occurrence_id=#{occurrence_id}" if occurrence_id

      response = get(url)
      unless response[:success]
        return { success: false, error: response[:error] }
      end

      event = response[:data]
      {
        success: true,
        tickets_sold: event["tickets_sold"].to_i,
        tickets_available: event["tickets_available"].to_i,
        capacity: (event["tickets_available"].to_i + event["tickets_sold"].to_i),
        revenue_cents: event["total_revenue_cents"].to_i,
        currency: event["currency"] || "USD"
      }
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
      handle_response(response)
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
      handle_response(response)
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
      handle_response(response)
    rescue StandardError => e
      handle_error(e)
    end

    def handle_response(response)
      # Update rate limit tracking if headers present
      if response["X-RateLimit-Remaining"]
        remaining = response["X-RateLimit-Remaining"].to_i
        reset_time = response["X-RateLimit-Reset"]&.to_i
        resets_at = reset_time ? Time.at(reset_time) : 1.minute.from_now
        provider.update_rate_limit_from_headers(remaining: remaining, resets_at: resets_at)
      end

      case response.code.to_i
      when 200..299
        { success: true, data: JSON.parse(response.body) }
      when 401
        raise AuthenticationError, "Invalid or expired API key"
      when 429
        reset_time = response["X-RateLimit-Reset"]&.to_i
        resets_at = reset_time ? Time.at(reset_time) : 1.minute.from_now
        raise RateLimitError.new("Rate limit exceeded", resets_at: resets_at)
      else
        error = JSON.parse(response.body).dig("message") rescue response.body
        { success: false, error: error }
      end
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

    # Normalize event data from Ticket Tailor API to common format
    def normalize_event(event, occurrence)
      event_id = event["id"]
      occurrence_id = occurrence&.dig("id")
      full_id = occurrence_id ? "#{event_id}:#{occurrence_id}" : event_id

      # Parse start time from the nested object structure
      start_time = if occurrence && occurrence["start"]
        parse_tt_datetime(occurrence["start"])
      elsif event["start"]
        parse_tt_datetime(event["start"])
      end

      venue = event["venue"] || {}
      capacity = event["tickets_available"].to_i + event["tickets_sold"].to_i

      {
        id: full_id,
        name: event["name"],
        title: event["name"],
        start_date: start_time,
        start: start_time,
        venue: { name: venue["name"] },
        venue_name: venue["name"],
        status: event["status"],
        tickets_sold: event["tickets_sold"].to_i,
        tickets_available: event["tickets_available"].to_i,
        capacity: capacity,
        revenue_cents: (event["revenue"].to_i * 100), # TT returns revenue in dollars
        url: event["url"],
        external_url: event["url"]
      }
    end

    # Parse Ticket Tailor datetime object to Ruby Time
    def parse_tt_datetime(dt)
      return nil unless dt

      if dt.is_a?(Hash)
        # Ticket Tailor returns { "iso": "2026-02-14T22:00:00-06:00", "unix": 1771128000, ... }
        if dt["iso"]
          Time.parse(dt["iso"]) rescue nil
        elsif dt["unix"]
          Time.at(dt["unix"]) rescue nil
        end
      else
        # Simple string
        Time.parse(dt.to_s) rescue nil
      end
    end
  end
end

# frozen_string_literal: true

module TicketingAdapters
  # Custom error classes for adapter operations
  class AdapterError < StandardError; end
  class AuthenticationError < AdapterError; end
  class RateLimitError < AdapterError
    attr_reader :resets_at, :remaining

    def initialize(message, resets_at: nil, remaining: 0)
      super(message)
      @resets_at = resets_at
      @remaining = remaining
    end
  end
  class ValidationError < AdapterError; end
  class NotFoundError < AdapterError; end

  class BaseAdapter
    attr_reader :provider

    # Default capabilities - override in subclasses
    CAPABILITIES = {
      "api_create_event" => false,
      "api_update_event" => false,
      "api_sync_inventory" => false,
      "api_fetch_sales" => false,
      "webhook_sales" => false,
      "webhook_inventory" => false,
      "webhook_event_updates" => false,
      "requires_approval" => false,
      "supports_draft" => false
    }.freeze

    def initialize(provider)
      @provider = provider
    end

    # ============================================
    # Capabilities
    # ============================================

    def capabilities
      self.class::CAPABILITIES
    end

    def can?(capability)
      capabilities[capability.to_s] == true
    end

    # Fields required for this provider to create a listing
    # Override in subclasses
    # @return [Hash<Symbol, Proc>] field_name => lambda that checks if field is present
    def required_fields
      {
        show_name: ->(listing) { listing.show_ticketing.show.display_name.present? },
        show_date: ->(listing) { listing.show_ticketing.show.date_and_time.present? },
        ticket_tiers: ->(listing) { listing.show_ticketing.show_ticket_tiers.any? }
      }
    end

    # ============================================
    # Core API Methods
    # ============================================

    # Test connection to the provider
    # @return [Hash] { success: Boolean, error: String? }
    def test_connection
      raise NotImplementedError, "Subclass must implement #test_connection"
    end

    # Create an event on the provider
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, event_id: String?, event_url: String?, error: String?, needs_approval: Boolean? }
    def create_event(listing)
      raise NotImplementedError, "Subclass must implement #create_event"
    end

    # Update event details on the provider
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, error: String? }
    def update_event(listing)
      raise NotImplementedError, "Subclass must implement #update_event"
    end

    # Update ticket inventory on the provider
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, error: String? }
    def update_inventory(listing)
      raise NotImplementedError, "Subclass must implement #update_inventory"
    end

    # Fetch sales from the provider
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, sales: Array, error: String? }
    def fetch_sales(listing)
      raise NotImplementedError, "Subclass must implement #fetch_sales"
    end

    # Full sync - pull all data for a listing
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, error: String? }
    def sync_listing(listing)
      raise NotImplementedError, "Subclass must implement #sync_listing"
    end

    # Check event status on provider (for approval workflows)
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, status: String, approved: Boolean?, error: String? }
    def check_event_status(listing)
      { success: true, status: "live", approved: true }
    end

    # ============================================
    # Webhook Methods
    # ============================================

    # Verify webhook signature
    # @param request [ActionDispatch::Request]
    # @return [Hash] { valid: Boolean, error: String? }
    def verify_webhook_signature(request)
      # Default: no verification
      { valid: true }
    end

    # Parse webhook payload into normalized event
    # @param payload [Hash]
    # @return [Hash] { event_type: String, data: Hash }
    def parse_webhook(payload)
      {
        event_type: payload["type"] || payload["event_type"] || "unknown",
        data: payload
      }
    end

    # ============================================
    # Data Transformation
    # ============================================

    # Transform show data into provider-specific format
    # @param listing [TicketListing]
    # @return [Hash] Provider-specific event data
    def build_event_payload(listing)
      show = listing.show_ticketing.show
      {
        name: show.display_name,
        description: show.description,
        start_time: show.date_and_time.iso8601,
        end_time: show.end_time&.iso8601,
        venue: build_venue_payload(show),
        tickets: build_tickets_payload(listing)
      }
    end

    def build_venue_payload(show)
      return nil unless show.location

      {
        name: show.location.name,
        address: show.location.address,
        city: show.location.city,
        state: show.location.state,
        postal_code: show.location.postal_code,
        country: show.location.country
      }
    end

    def build_tickets_payload(listing)
      listing.show_ticketing.show_ticket_tiers.map do |tier|
        {
          name: tier.name,
          price_cents: tier.default_price_cents,
          quantity: tier.available
        }
      end
    end

    protected

    def api_key
      provider.api_key
    end

    def api_secret
      provider.api_secret
    end

    def settings
      provider.settings || {}
    end

    # ============================================
    # Rate Limit Handling
    # ============================================

    def check_rate_limit!
      raise RateLimitError.new("Rate limited", resets_at: provider.rate_limited_until) if provider.rate_limited?
    end

    def update_rate_limits_from_response(response)
      return unless response.respond_to?(:headers)

      remaining = response.headers["X-RateLimit-Remaining"]&.to_i
      reset_time = response.headers["X-RateLimit-Reset"]

      if remaining && reset_time
        resets_at = Time.at(reset_time.to_i)
        provider.update_rate_limit_from_headers(remaining: remaining, resets_at: resets_at)
      end
    end

    # ============================================
    # Logging
    # ============================================

    def log_info(message)
      Rails.logger.info "[#{self.class.name}] #{message}"
    end

    def log_error(message)
      Rails.logger.error "[#{self.class.name}] #{message}"
    end

    def handle_error(error)
      log_error("Error: #{error.message}")
      { success: false, error: error.message }
    end

    def handle_auth_error(error)
      log_error("Authentication error: #{error.message}")
      { success: false, error: error.message, auth_error: true }
    end

    def handle_rate_limit_error(error)
      log_error("Rate limit error: #{error.message}")
      { success: false, error: error.message, rate_limited: true }
    end
  end
end

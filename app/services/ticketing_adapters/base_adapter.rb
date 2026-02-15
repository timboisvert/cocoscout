# frozen_string_literal: true

module TicketingAdapters
  class BaseAdapter
    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # Test connection to the provider
    # @return [Hash] { success: Boolean, error: String? }
    def test_connection
      raise NotImplementedError, "Subclass must implement #test_connection"
    end

    # Create an event on the provider
    # @param listing [TicketListing]
    # @return [Hash] { success: Boolean, event_id: String?, event_url: String?, error: String? }
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
  end
end

# frozen_string_literal: true

module TicketingWebhooks
  class BaseHandler
    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # Process a webhook log entry
    # @param webhook_log [WebhookLog]
    # @return [Hash] { success: Boolean, error: String?, duplicate: Boolean?, ignored: Boolean?, reason: String? }
    def process(webhook_log)
      payload = webhook_log.parsed_payload
      event_type = webhook_log.event_type

      case event_type
      when /order|purchase|ticket\.sold|sale/i
        handle_sale(webhook_log, payload)
      when /refund|cancel/i
        handle_refund(webhook_log, payload)
      when /event\.update|event\.change/i
        handle_event_update(webhook_log, payload)
      when /event\.publish|event\.live/i
        handle_event_published(webhook_log, payload)
      when /event\.cancel|event\.delete/i
        handle_event_cancelled(webhook_log, payload)
      else
        { success: true, ignored: true, reason: "Unknown event type: #{event_type}" }
      end
    rescue StandardError => e
      { success: false, error: e.message }
    end

    protected

    # Override in subclasses for provider-specific handling
    def handle_sale(webhook_log, payload)
      { success: true, ignored: true, reason: "Sale handling not implemented" }
    end

    def handle_refund(webhook_log, payload)
      { success: true, ignored: true, reason: "Refund handling not implemented" }
    end

    def handle_event_update(webhook_log, payload)
      { success: true, ignored: true, reason: "Event update handling not implemented" }
    end

    def handle_event_published(webhook_log, payload)
      { success: true, ignored: true, reason: "Event published handling not implemented" }
    end

    def handle_event_cancelled(webhook_log, payload)
      { success: true, ignored: true, reason: "Event cancelled handling not implemented" }
    end

    # Find the ticket listing associated with this webhook
    def find_listing(external_event_id)
      return nil if external_event_id.blank?

      provider.ticket_listings.find_by(external_event_id: external_event_id)
    end

    # Find an existing sale by external ID
    def find_existing_sale(external_sale_id)
      return nil if external_sale_id.blank?

      TicketSale.joins(ticket_offer: :ticket_listing)
                .where(ticket_listings: { ticketing_provider_id: provider.id })
                .find_by(external_sale_id: external_sale_id)
    end

    def log_info(message)
      Rails.logger.info "[#{self.class.name}] #{message}"
    end

    def log_error(message)
      Rails.logger.error "[#{self.class.name}] #{message}"
    end
  end
end

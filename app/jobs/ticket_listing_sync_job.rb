# frozen_string_literal: true

class TicketListingSyncJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff on rate limits
  retry_on TicketingAdapters::RateLimitError, wait: :polynomially_longer, attempts: 5

  def perform(listing_id, operation: :sync)
    listing = TicketListing.find_by(id: listing_id)

    unless listing
      Rails.logger.warn "[TicketListingSyncJob] Listing #{listing_id} not found"
      return
    end

    provider = listing.ticketing_provider

    # Check if provider can sync
    unless provider.can_sync?
      if provider.rate_limited?
        # Re-queue for after rate limit
        self.class.set(wait_until: provider.rate_limited_until).perform_later(listing_id, operation: operation)
        Rails.logger.info "[TicketListingSyncJob] Provider rate limited, re-queued for #{provider.rate_limited_until}"
        return
      elsif !provider.credentials_healthy?
        Rails.logger.warn "[TicketListingSyncJob] Provider credentials unhealthy, skipping"
        listing.update!(status: :auth_expired) unless listing.status_auth_expired?
        return
      end
    end

    Rails.logger.info "[TicketListingSyncJob] #{operation} listing: #{listing.display_name}"

    result = case operation.to_sym
    when :sync
      listing.sync!
    when :pull_sales
      listing.pull_sales!
    when :push_inventory
      listing.push_inventory!
    else
      listing.sync!
    end

    if result[:success]
      Rails.logger.info "[TicketListingSyncJob] Successfully completed #{operation} for listing #{listing_id}"
    else
      Rails.logger.error "[TicketListingSyncJob] Failed #{operation} for listing #{listing_id}: #{result[:error]}"
    end
  rescue TicketingAdapters::AuthenticationError => e
    Rails.logger.error "[TicketListingSyncJob] Auth error for listing #{listing_id}: #{e.message}"
    listing.ticketing_provider.mark_credentials_invalid!(e.message)
    listing.update!(status: :auth_expired)
  rescue TicketingAdapters::RateLimitError => e
    Rails.logger.warn "[TicketListingSyncJob] Rate limited for listing #{listing_id}, will retry"
    listing.ticketing_provider.record_rate_limit!(resets_at: e.resets_at)
    raise # Let retry_on handle it
  end
end

# frozen_string_literal: true

class TicketingProviderSyncJob < ApplicationJob
  queue_as :default

  def perform(provider_id)
    provider = TicketingProvider.find_by(id: provider_id)

    unless provider
      Rails.logger.warn "[TicketingProviderSyncJob] Provider #{provider_id} not found"
      return
    end

    # Skip manual providers
    if provider.manual_only?
      Rails.logger.info "[TicketingProviderSyncJob] Skipping manual provider #{provider.name}"
      return
    end

    unless provider.configured?
      Rails.logger.warn "[TicketingProviderSyncJob] Provider #{provider.name} not configured"
      return
    end

    # Check rate limiting
    if provider.rate_limited?
      Rails.logger.info "[TicketingProviderSyncJob] Provider #{provider.name} rate limited until #{provider.rate_limited_until}"
      # Re-queue for after rate limit
      self.class.set(wait_until: provider.rate_limited_until + 1.minute).perform_later(provider_id)
      return
    end

    # Check credentials
    unless provider.credentials_healthy?
      Rails.logger.warn "[TicketingProviderSyncJob] Provider #{provider.name} credentials unhealthy"
      # Mark all active listings
      provider.ticket_listings.where(status: %w[live ready pending_sync]).update_all(status: :auth_expired)
      return
    end

    Rails.logger.info "[TicketingProviderSyncJob] Syncing provider: #{provider.name}"

    synced = 0
    errors = []
    rate_limited = false

    # Get listings that need sync
    listings = provider.ticket_listings.selling.due_for_sync

    listings.find_each do |listing|
      break if rate_limited

      begin
        result = listing.pull_sales!

        if result[:success]
          synced += 1
        elsif result[:rate_limited]
          rate_limited = true
        else
          errors << { listing_id: listing.id, error: result[:error] }
        end
      rescue TicketingAdapters::RateLimitError => e
        rate_limited = true
        provider.record_rate_limit!(resets_at: e.resets_at)
        Rails.logger.warn "[TicketingProviderSyncJob] Rate limited, stopping sync"
      rescue TicketingAdapters::AuthenticationError => e
        provider.mark_credentials_invalid!(e.message)
        Rails.logger.error "[TicketingProviderSyncJob] Auth error, stopping sync"
        break
      rescue StandardError => e
        errors << { listing_id: listing.id, error: e.message }
      end
    end

    provider.update!(last_synced_at: Time.current) unless rate_limited

    Rails.logger.info "[TicketingProviderSyncJob] Synced #{synced} listings for #{provider.name}"

    if errors.any?
      Rails.logger.warn "[TicketingProviderSyncJob] #{errors.count} errors for #{provider.name}"
    end

    if rate_limited
      Rails.logger.info "[TicketingProviderSyncJob] Will resume after rate limit clears"
    end
  end
end

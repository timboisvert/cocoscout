# frozen_string_literal: true

class TicketingProviderSyncJob < ApplicationJob
  queue_as :default

  def perform(provider_id)
    provider = TicketingProvider.find_by(id: provider_id)

    unless provider
      Rails.logger.warn "[TicketingProviderSyncJob] Provider #{provider_id} not found"
      return
    end

    unless provider.configured?
      Rails.logger.warn "[TicketingProviderSyncJob] Provider #{provider.name} not configured"
      return
    end

    Rails.logger.info "[TicketingProviderSyncJob] Syncing provider: #{provider.name}"

    synced = 0
    errors = []

    provider.ticket_listings.active.find_each do |listing|
      result = listing.sync!

      if result[:success]
        synced += 1
      else
        errors << { listing_id: listing.id, error: result[:error] }
      end
    end

    provider.update!(last_synced_at: Time.current)

    Rails.logger.info "[TicketingProviderSyncJob] Synced #{synced} listings for #{provider.name}"

    if errors.any?
      Rails.logger.warn "[TicketingProviderSyncJob] #{errors.count} errors for #{provider.name}: #{errors.map { |e| e[:error] }.join(', ')}"
    end
  end
end

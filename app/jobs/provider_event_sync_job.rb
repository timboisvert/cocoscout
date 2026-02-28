# frozen_string_literal: true

# ProviderEventSyncJob syncs events from all active ticketing providers.
# This builds the provider-side data model (ProviderEvent → RemoteTicketingEvent)
# which maps to our Production → Show hierarchy.
#
# Runs every 60 minutes to keep provider events up to date.
#
class ProviderEventSyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[ProviderEventSync] Starting sync for all providers"

    providers = TicketingProvider
      .status_active
      .api_enabled
      .with_valid_credentials
      .not_rate_limited

    total_stats = {
      providers_synced: 0,
      events_created: 0,
      events_updated: 0,
      occurrences_created: 0,
      occurrences_updated: 0,
      errors: []
    }

    providers.find_each do |provider|
      sync_provider(provider, total_stats)
    end

    Rails.logger.info "[ProviderEventSync] Complete: #{total_stats}"
  end

  private

  def sync_provider(provider, total_stats)
    Rails.logger.info "[ProviderEventSync] Syncing #{provider.name}"

    service = ProviderSyncService.new(provider)
    stats = service.sync!

    total_stats[:providers_synced] += 1
    total_stats[:events_created] += stats[:events_created]
    total_stats[:events_updated] += stats[:events_updated]
    total_stats[:occurrences_created] += stats[:occurrences_created]
    total_stats[:occurrences_updated] += stats[:occurrences_updated]
    total_stats[:errors].concat(stats[:errors]) if stats[:errors].any?
  rescue => e
    Rails.logger.error "[ProviderEventSync] Failed to sync #{provider.name}: #{e.message}"
    total_stats[:errors] << "#{provider.name}: #{e.message}"
  end
end

# frozen_string_literal: true

class TicketingSyncJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for rate limits
  retry_on Ticketing::BaseService::RateLimitError,
           wait: :polynomially_longer,
           attempts: 5

  # Retry API errors a few times
  retry_on Ticketing::BaseService::ApiError,
           wait: 5.minutes,
           attempts: 3

  # Don't retry auth errors - need user intervention
  discard_on Ticketing::BaseService::AuthenticationError

  def perform(ticketing_provider_id, production_link_id: nil)
    provider = TicketingProvider.find_by(id: ticketing_provider_id)
    return unless provider
    return unless provider.auto_sync_enabled?
    return unless provider.healthy?

    coordinator = Ticketing::SyncCoordinator.new(provider)

    if production_link_id
      # Sync specific production
      production_link = provider.ticketing_production_links.find_by(id: production_link_id)
      coordinator.sync_production(production_link) if production_link
    else
      # Sync all productions for this provider
      coordinator.sync_all
    end
  end
end

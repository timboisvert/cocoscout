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

  def perform(ticketing_provider_id, sync_type: :full)
    provider = TicketingProvider.find_by(id: ticketing_provider_id)
    return unless provider
    return unless provider.auto_sync_enabled?
    return unless provider.healthy?

    case sync_type.to_sym
    when :full
      # Full sync: discover events, auto-link, then sync sales
      full_sync(provider)
    when :events_only
      # Just discover and link events
      discover_events(provider)
    when :sales_only
      # Just sync sales for existing links
      sync_sales(provider)
    end
  end

  private

  def full_sync(provider)
    # Step 1: Discover and auto-link events
    link_result = discover_events(provider)

    # Step 2: Sync sales for all linked productions
    sales_result = sync_sales(provider)

    # Log results
    log_sync_results(provider, link_result, sales_result)

    # Update provider status
    if sales_result[:success]
      provider.mark_sync_success!
    else
      provider.mark_sync_failure!(sales_result[:errors].first)
    end
  end

  def discover_events(provider)
    auto_linker = Ticketing::Operations::AutoLinkEvents.new(provider)
    auto_linker.call
  end

  def sync_sales(provider)
    coordinator = Ticketing::SyncCoordinator.new(provider)
    coordinator.sync_all
  end

  def log_sync_results(provider, link_result, sales_result)
    Rails.logger.info(
      "[TicketingSync] Provider #{provider.id} (#{provider.name}): " \
      "Linked #{link_result[:linked].size} events, " \
      "#{link_result[:pending].size} pending, " \
      "#{sales_result[:productions_synced]} productions synced"
    )

    if link_result[:errors].any?
      Rails.logger.warn(
        "[TicketingSync] Provider #{provider.id} link errors: #{link_result[:errors].join(', ')}"
      )
    end

    if sales_result[:errors].any?
      Rails.logger.warn(
        "[TicketingSync] Provider #{provider.id} sales errors: #{sales_result[:errors].join(', ')}"
      )
    end
  end
end

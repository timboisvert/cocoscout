# frozen_string_literal: true

class TicketingSetupSyncJob < ApplicationJob
  queue_as :default

  # Sync a production's ticketing setup with all configured providers
  # Compares what SHOULD exist (rules) with what DOES exist (remote events)
  def perform(setup_id)
    setup = ProductionTicketingSetup.find_by(id: setup_id)

    unless setup
      Rails.logger.warn "[TicketingSetupSyncJob] Setup #{setup_id} not found"
      return
    end

    unless setup.status_active?
      Rails.logger.info "[TicketingSetupSyncJob] Setup #{setup_id} is not active, skipping"
      return
    end

    @production = setup.production
    @stats = { created: 0, updated: 0, deleted: 0, errors: 0 }

    Rails.logger.info "[TicketingSetupSyncJob] Starting sync for #{@production.name}"

    # Broadcast sync started
    TicketingChannel.broadcast_engine_status(@production, "syncing", "Starting sync...")
    TicketingActivity.log!(@production, "sync_started", "Sync started")

    setup.provider_setups.enabled.each do |provider_setup|
      sync_provider(setup, provider_setup)
    end

    # Broadcast sync complete
    message = "Sync complete: #{@stats[:created]} created, #{@stats[:updated]} updated"
    message += ", #{@stats[:errors]} errors" if @stats[:errors] > 0
    TicketingChannel.broadcast_engine_status(@production, "active", message)
    TicketingActivity.log!(@production, "sync_complete", message, data: @stats)

    setup.update!(last_synced_at: Time.current)

    Rails.logger.info "[TicketingSetupSyncJob] Completed sync for #{@production.name}"
  end

  private

  def sync_provider(setup, provider_setup)
    provider = provider_setup.ticketing_provider

    unless provider.configured?
      Rails.logger.warn "[TicketingSetupSyncJob] Provider #{provider.name} not configured"
      return
    end

    if provider.rate_limited?
      Rails.logger.info "[TicketingSetupSyncJob] Provider #{provider.name} rate limited"
      # Re-queue for later
      self.class.set(wait_until: provider.rate_limited_until + 1.minute).perform_later(setup.id)
      return
    end

    # Get shows that SHOULD be listed
    should_list_ids = setup.shows_to_list.pluck(:id)

    # Get shows that ARE listed (have remote events)
    have_remote = setup.remote_ticketing_events
                       .where(ticketing_provider: provider)
                       .where.not(sync_status: :deleted)

    listed_show_ids = have_remote.pluck(:show_id).compact

    # Calculate what needs to happen
    to_create = should_list_ids - listed_show_ids
    to_delete = listed_show_ids - should_list_ids
    to_sync = should_list_ids & listed_show_ids

    Rails.logger.info "[TicketingSetupSyncJob] Provider #{provider.name}: " \
                      "create=#{to_create.count}, delete=#{to_delete.count}, sync=#{to_sync.count}"

    # Create new remote events
    Show.where(id: to_create).find_each do |show|
      create_remote_event(setup, provider_setup, show)
    end

    # Delete orphaned remote events
    have_remote.where(show_id: to_delete).find_each do |event|
      delete_remote_event(event)
    end

    # Sync existing remote events (check for updates needed)
    have_remote.where(show_id: to_sync).find_each do |event|
      sync_remote_event(setup, provider_setup, event)
    end
  rescue TicketingAdapters::RateLimitError => e
    provider_setup.ticketing_provider.record_rate_limit!(resets_at: e.resets_at)
    Rails.logger.warn "[TicketingSetupSyncJob] Rate limited on #{provider_setup.ticketing_provider.name}"
  rescue TicketingAdapters::AuthenticationError => e
    provider_setup.ticketing_provider.mark_credentials_invalid!(e.message)
    Rails.logger.error "[TicketingSetupSyncJob] Auth error on #{provider_setup.ticketing_provider.name}"
  end

  def create_remote_event(setup, provider_setup, show)
    # Check if show should be listed on this provider
    return unless setup.should_list?(show, provider_setup.ticketing_provider)

    event_data = setup.event_data_for(show)
    provider = provider_setup.ticketing_provider

    Rails.logger.info "[TicketingSetupSyncJob] Creating event for show #{show.id} on #{provider.name}"

    # Broadcast syncing status
    TicketingChannel.broadcast_show_sync(@production, show.id, "syncing", "Creating on #{provider.name}...", provider: provider.name)

    # Create local tracking record first
    remote_event = setup.remote_ticketing_events.create!(
      ticketing_provider: provider,
      show: show,
      organization: setup.organization,
      external_event_id: "pending_#{SecureRandom.hex(8)}",
      sync_status: :pending_create,
      raw_data: event_data
    )

    # Push to provider
    adapter = TicketingAdapters.adapter_for(provider)
    result = adapter.create_event(
      event_data.merge(
        image_url: setup.image_for_provider(provider)&.then { |img| Rails.application.routes.url_helpers.rails_blob_url(img, host: Rails.application.config.action_mailer.default_url_options[:host]) }
      )
    )

    if result[:success]
      remote_event.update!(
        external_event_id: result[:event_id],
        external_url: result[:url],
        sync_status: :synced,
        last_synced_at: Time.current,
        remote_status: :draft
      )
      Rails.logger.info "[TicketingSetupSyncJob] Created event #{result[:event_id]} for show #{show.id}"

      # Broadcast success
      @stats[:created] += 1
      TicketingChannel.broadcast_show_sync(@production, show.id, "listed", "Listed on #{provider.name}", provider: provider.name)
      TicketingActivity.log!(@production, "listing_created", "Created listing on #{provider.name}", show: show, data: { provider: provider.name, event_id: result[:event_id] })
    else
      remote_event.update!(
        sync_status: :error,
        last_sync_error: result[:error]
      )
      Rails.logger.error "[TicketingSetupSyncJob] Failed to create event: #{result[:error]}"

      # Broadcast error
      @stats[:errors] += 1
      TicketingChannel.broadcast_show_sync(@production, show.id, "error", result[:error], provider: provider.name)
      TicketingActivity.log!(@production, "error", "Failed to create on #{provider.name}: #{result[:error]}", show: show, data: { provider: provider.name, error: result[:error] })
    end
  rescue StandardError => e
    @stats[:errors] += 1
    TicketingChannel.broadcast_show_sync(@production, show.id, "error", e.message, provider: provider_setup.ticketing_provider.name)
    Rails.logger.error "[TicketingSetupSyncJob] Error creating event for show #{show.id}: #{e.message}"
  end

  def delete_remote_event(remote_event)
    provider = remote_event.ticketing_provider

    Rails.logger.info "[TicketingSetupSyncJob] Deleting event #{remote_event.external_event_id} on #{provider.name}"

    remote_event.update!(sync_status: :pending_delete)

    adapter = TicketingAdapters.adapter_for(provider)
    result = adapter.delete_event(remote_event.external_event_id)

    if result[:success]
      remote_event.update!(
        sync_status: :deleted,
        last_synced_at: Time.current
      )
      Rails.logger.info "[TicketingSetupSyncJob] Deleted event #{remote_event.external_event_id}"
    else
      remote_event.update!(
        sync_status: :error,
        last_sync_error: result[:error]
      )
      Rails.logger.error "[TicketingSetupSyncJob] Failed to delete event: #{result[:error]}"
    end
  rescue StandardError => e
    Rails.logger.error "[TicketingSetupSyncJob] Error deleting event #{remote_event.id}: #{e.message}"
  end

  def sync_remote_event(setup, provider_setup, remote_event)
    show = remote_event.show
    return unless show # Show may have been deleted

    event_data = setup.event_data_for(show)

    # Check if update needed by comparing cached snapshot
    if remote_event.needs_update?(event_data)
      Rails.logger.info "[TicketingSetupSyncJob] Updating event #{remote_event.external_event_id}"

      remote_event.update!(sync_status: :pending_update)

      adapter = TicketingAdapters.adapter_for(remote_event.ticketing_provider)
      result = adapter.update_event(remote_event.external_event_id, event_data)

      if result[:success]
        remote_event.update!(
          sync_status: :synced,
          raw_data: event_data,
          last_synced_at: Time.current
        )
      else
        remote_event.update!(
          sync_status: :error,
          last_sync_error: result[:error]
        )
      end
    end

    # Always pull latest sales data
    pull_sales_data(remote_event)
  rescue StandardError => e
    Rails.logger.error "[TicketingSetupSyncJob] Error syncing event #{remote_event.id}: #{e.message}"
  end

  def pull_sales_data(remote_event)
    adapter = TicketingAdapters.adapter_for(remote_event.ticketing_provider)
    result = adapter.get_sales(remote_event.external_event_id)

    if result[:success]
      old_sold = remote_event.tickets_sold || 0
      new_sold = result[:tickets_sold] || 0

      remote_event.update!(
        tickets_sold: new_sold,
        tickets_available: result[:tickets_available],
        revenue_cents: result[:revenue_cents],
        last_synced_at: Time.current
      )

      # Broadcast sales update if changed
      if new_sold != old_sold && remote_event.show.present?
        TicketingChannel.broadcast_sales_update(
          @production,
          remote_event.show_id,
          sold: new_sold,
          available: result[:tickets_available],
          provider: remote_event.ticketing_provider.name
        )

        # Log significant sales changes
        if new_sold > old_sold
          tickets_sold = new_sold - old_sold
          message = "#{tickets_sold} #{'ticket'.pluralize(tickets_sold)} sold on #{remote_event.ticketing_provider.name}"
          TicketingActivity.log!(@production, "sales_received", message, show: remote_event.show, data: { sold: tickets_sold, total: new_sold, provider: remote_event.ticketing_provider.name })
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "[TicketingSetupSyncJob] Error pulling sales for #{remote_event.id}: #{e.message}"
  end
end

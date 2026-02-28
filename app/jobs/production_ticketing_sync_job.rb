# frozen_string_literal: true

# Recurring job that syncs all active production ticketing setups
# Runs every 5 minutes to ensure listings are up to date
class ProductionTicketingSyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[ProductionTicketingSyncJob] Starting sync for all active setups"

    count = 0
    ProductionTicketingSetup.active_setups.includes(:production).find_each do |setup|
      # Skip if recently synced (within last 3 minutes)
      next if setup.last_synced_at && setup.last_synced_at > 3.minutes.ago

      Rails.logger.info "[ProductionTicketingSyncJob] Queuing sync for #{setup.production.name}"
      TicketingSetupSyncJob.perform_later(setup.id)
      count += 1
    end

    Rails.logger.info "[ProductionTicketingSyncJob] Queued #{count} setups for sync"
  end
end

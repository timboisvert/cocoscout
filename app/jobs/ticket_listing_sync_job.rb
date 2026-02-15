# frozen_string_literal: true

class TicketListingSyncJob < ApplicationJob
  queue_as :default

  def perform(listing_id)
    listing = TicketListing.find_by(id: listing_id)

    unless listing
      Rails.logger.warn "[TicketListingSyncJob] Listing #{listing_id} not found"
      return
    end

    Rails.logger.info "[TicketListingSyncJob] Syncing listing: #{listing.display_name}"

    # Pull latest sales data
    result = listing.pull_sales!

    if result[:success]
      Rails.logger.info "[TicketListingSyncJob] Successfully synced listing #{listing_id}"
    else
      Rails.logger.error "[TicketListingSyncJob] Failed to sync listing #{listing_id}: #{result[:error]}"
    end
  end
end

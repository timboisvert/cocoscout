# frozen_string_literal: true

# Offers returned seats to the waitlist (Ticketing::Waitlist.sweep!): on
# every seat-return event (a refund, a move, a lapsed hold, a released group
# or subscription) for that date, and every five minutes for every date.
class WaitlistOfferJob < ApplicationJob
  queue_as :default

  def perform(listing_id = nil)
    listing = listing_id && TicketListing.find_by(id: listing_id)
    return if listing_id && listing.nil?

    Ticketing::Waitlist.sweep!(listing)
  end
end

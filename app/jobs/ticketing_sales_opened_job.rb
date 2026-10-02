# frozen_string_literal: true

# Every 15 minutes: shows whose scheduled on-sale time has come tell the
# theater they're selling (once each).
class TicketingSalesOpenedJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    TicketListing.where(status: "on_sale", on_sale_at: (now - 1.day)..now).includes(:organization, :show).find_each do |listing|
      next unless listing.organization.ticketing_profile&.enabled?

      TicketingNotifier.notify(listing.organization, :sales_opened, variables: TicketingNotificationContent.milestone(listing),
                                                                    about: listing, once: true)
    end
  end
end

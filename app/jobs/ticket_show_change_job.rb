# frozen_string_literal: true

# Tells each buyer of a moved show, in the manager's words (see
# TicketShowChange). Each order is marked told as its email goes, so a rerun
# only reaches whoever is left.
class TicketShowChangeJob < ApplicationJob
  queue_as :default

  def perform(listing_id, subject, body)
    listing = TicketListing.find_by(id: listing_id)
    return unless listing

    TicketShowChange.orders(listing).find_each do |order|
      TicketOrderMailer.changed(order, subject: subject, body: body).deliver_now
      TicketShowChange.mark_told!(listing, TicketOrder.where(id: order.id))
    end
  end
end

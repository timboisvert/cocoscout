# frozen_string_literal: true

# Refunds every online buyer of a canceled show, then sends each the
# manager's email. Talks to Stripe once per order, so it runs off the request
# thread. Re-runnable: an order already refunded is no longer paid, so a
# retry only touches what's left. A refund that fails leaves its order paid —
# on the Orders page, never silently lost.
class TicketShowCancellationJob < ApplicationJob
  queue_as :default

  def perform(listing_id, subject, body, user_id = nil)
    listing = TicketListing.find_by(id: listing_id)
    return unless listing&.status == "canceled"

    user = User.find_by(id: user_id)
    TicketShowCancellation.orders(listing).find_each do |order|
      refund = TicketOrderRefund.issue!(order, by: user, reason: "Show canceled", notify: false)
      TicketOrderMailer.canceled(refund, subject: subject, body: body).deliver_later if order.buyer_email.present?
    rescue TicketOrderRefund::Error => e
      Rails.logger.warn("[TicketShowCancellationJob] order #{order.id}: #{e.message}")
    end
  end
end

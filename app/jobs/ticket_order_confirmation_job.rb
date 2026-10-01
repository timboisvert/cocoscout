# frozen_string_literal: true

# Sends a buyer their tickets, off the request thread (QR codes take a moment
# to draw, and a mail hiccup must never fail a payment).
class TicketOrderConfirmationJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = TicketOrder.find_by(id: order_id)
    return unless order&.paid? && order.buyer_email.present?

    TicketOrderMailer.confirmation(order).deliver_now
  end
end

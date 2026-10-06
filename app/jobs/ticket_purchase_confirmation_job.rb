# frozen_string_literal: true

# Sends a buyer of several shows (a pass) one email with every show's
# tickets, off the request thread like a single order's.
class TicketPurchaseConfirmationJob < ApplicationJob
  queue_as :default

  def perform(purchase_id)
    purchase = TicketPurchase.find_by(id: purchase_id)
    return unless purchase&.paid?

    orders = purchase.ticket_orders.select(&:paid?)
    return if orders.empty? || orders.first.buyer_email.blank?

    TicketOrderMailer.purchase_confirmation(purchase).deliver_now
  end
end

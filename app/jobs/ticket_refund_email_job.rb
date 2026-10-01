# frozen_string_literal: true

# Tells a buyer their refund is on its way, off the request thread.
class TicketRefundEmailJob < ApplicationJob
  queue_as :default

  def perform(refund_id)
    refund = TicketRefund.find_by(id: refund_id)
    return unless refund&.status == "succeeded" && refund.ticket_order.buyer_email.present?

    TicketOrderMailer.refunded(refund).deliver_now
  end
end

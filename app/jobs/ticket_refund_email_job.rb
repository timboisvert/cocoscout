# frozen_string_literal: true

# Tells a buyer their refund is on its way, off the request thread; or,
# when nothing was paid (a comp), that their tickets were canceled.
class TicketRefundEmailJob < ApplicationJob
  queue_as :default

  def perform(refund_id)
    refund = TicketRefund.find_by(id: refund_id)
    return unless refund&.status == "succeeded" && refund.ticket_order.buyer_email.present?

    if refund.amount_cents.positive?
      TicketOrderMailer.refunded(refund).deliver_now
    else
      TicketOrderMailer.tickets_canceled(refund).deliver_now
    end
  end
end

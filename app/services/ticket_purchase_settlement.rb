# frozen_string_literal: true

# A purchase's money arrived: every show's order in it settles
# (TicketOrderSettlement: its tickets, its show's balance and books, its
# financials). Idempotent, like the order's: the webhook and the buyer's
# return both call it. The first order records the payment's ids.
#
# Money that arrives after the hold ran out still counts when every show
# still has the seats. If any show's are gone, the whole purchase is refunded
# rather than half of it kept.
class TicketPurchaseSettlement
  def self.settle!(purchase, payment_intent_id: nil, charge_id: nil)
    go = false
    purchase.with_lock do
      next if purchase.paid? || purchase.status == "canceled"

      orders = purchase.ticket_orders.to_a
      late = purchase.hold_expired? || purchase.status == "expired"
      if late && orders.any? { |order| order.status.in?(%w[pending expired]) && !TicketOrderSettlement.seats_still_free?(order) }
        refund_late_payment!(purchase, payment_intent_id)
        next
      end

      purchase.update!(status: "paid", paid_at: Time.current, expires_at: nil,
                       stripe_payment_intent_id: payment_intent_id || purchase.stripe_payment_intent_id,
                       stripe_charge_id: charge_id || purchase.stripe_charge_id)
      go = true
    end
    return purchase unless go

    purchase.ticket_orders.each_with_index do |order, index|
      TicketOrderSettlement.settle!(order, payment_intent_id: (payment_intent_id if index.zero?),
                                           charge_id: (charge_id if index.zero?), seats_checked: true)
    end
    purchase
  end

  def self.refund_late_payment!(purchase, payment_intent_id)
    intent_id = payment_intent_id || purchase.stripe_payment_intent_id
    Stripe::Refund.create({ payment_intent: intent_id }, { idempotency_key: "ticket-purchase-late-refund-#{purchase.id}" }) if intent_id
    now = Time.current
    purchase.update!(status: "canceled", stripe_payment_intent_id: intent_id)
    purchase.ticket_orders.each do |order|
      order.update!(status: "canceled", canceled_at: now)
      order.tickets.update_all(status: "void", updated_at: now)
    end
    Rails.logger.warn("[TicketPurchaseSettlement] purchase #{purchase.id} paid after its seats were gone; refunded")
  end

  private_class_method :refund_late_payment!
end

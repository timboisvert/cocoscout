# frozen_string_literal: true

# A ticket order's money arrived. Idempotent — the webhook and the buyer's
# return from Stripe both call it, and only the first one does anything:
#   - the held tickets become real;
#   - the theater's CocoScout balance gets what it nets (OrgCashEntry);
#   - the books record the sale (LedgerPosting): the ticket money waits in
#     "Tickets sold for upcoming shows" until the show happens, tax goes to
#     "Tax to pay the government", fees net against buyer-paid fees;
#   - the show's financials get their CocoScout Tickets row;
#   - the buyer gets their tickets by email.
#
# Money that arrives after the hold ran out still counts if the seats are
# still there; if they've gone, the buyer is refunded.
class TicketOrderSettlement
  class SeatsGone < StandardError; end

  # seats_checked: a purchase already made sure every order's seats are still
  # there (TicketPurchaseSettlement), so a late payment never splits it.
  def self.settle!(order, payment_intent_id: nil, charge_id: nil, seats_checked: false)
    settled = false
    order.with_lock do
      next if order.paid? || %w[refunded canceled exchanged].include?(order.status)

      ensure_seats_still_free!(order) if !seats_checked && (order.hold_expired? || order.status == "expired")
      order.told_current_show!
      order.update!(status: "paid", paid_at: Time.current, expires_at: nil,
                    stripe_payment_intent_id: payment_intent_id || order.stripe_payment_intent_id,
                    stripe_charge_id: charge_id || order.stripe_charge_id)
      if order.channel == "door_card"
        # Paid standing at the door: they're in.
        order.tickets.where(status: "reserved").update_all(status: "checked_in", checked_in_at: Time.current,
                                                           checked_in_by_id: order.issued_by_id, updated_at: Time.current)
      else
        order.tickets.where(status: "reserved").update_all(status: "valid", updated_at: Time.current)
      end
      order.ticket_order_items.where(status: "reserved").update_all(status: "valid", updated_at: Time.current)
      TaxLine.where(taxable_type: "Ticket", taxable_id: order.tickets.select(:id)).update_all(sale_date: Date.current)
      TaxLine.where(taxable_type: "TicketOrderItem", taxable_id: order.ticket_order_items.select(:id)).update_all(sale_date: Date.current)
      post_money!(order)
      settled = true
    end

    if settled
      TicketSalesSync.sync!(order.ticket_listing.show)
      TicketOrderConfirmationJob.perform_later(order.id) if order.buyer_email.present?
      TicketingAfterSaleJob.perform_later(order.id)
    end
    order
  rescue SeatsGone
    refund_late_payment!(order, payment_intent_id)
    order
  end

  # The books lines for a sale through CocoScout (see the class comment).
  # Products bought with the tickets wait in their own advance account.
  def self.sale_lines(order)
    listing = order.ticket_listing
    product_face = product_face_cents(order)
    included_tax = TaxLine.where(taxable_type: "Ticket", taxable_id: order.tickets.select(:id), included: true).sum(:tax_cents)
    # The order's subtotal holds tickets and products together.
    face = order.subtotal_cents - order.discount_cents - included_tax - product_face_with_included_tax(order)
    dims = { show: listing.show, production: listing.production }
    [
      { account: :cocoscout_balance, amount_cents: order.org_net_cents },
      { account: :ticketing_fees, amount_cents: order.platform_fee_cents + order.processing_cents },
      { account: :fees_paid_by_buyers, amount_cents: -order.buyer_fee_cents },
      { account: :advance_ticket_sales, amount_cents: -face, **dims },
      { account: :advance_product_sales, amount_cents: -product_face, **dims },
      { account: :tax_to_remit, amount_cents: -order.tax_cents, **dims }
    ]
  end

  # What the order's products sold for, without any tax inside their price.
  def self.product_face_cents(order)
    product_face_with_included_tax(order) -
      TaxLine.where(taxable_type: "TicketOrderItem", taxable_id: order.ticket_order_items.select(:id), included: true).sum(:tax_cents)
  end

  def self.product_face_with_included_tax(order)
    order.ticket_order_items.sum("unit_price_cents * quantity").to_i
  end

  def self.post_money!(order)
    return unless order.money_path == "cocoscout" && order.total_cents.positive?

    OrgCashEntry.post!(organization: order.organization, entry_type: "ticket_sale", amount_cents: order.org_net_cents,
                       source: order, description: "Tickets #{order.code}", occurred_at: order.paid_at)
    LedgerPosting.post!(organization: order.organization, source: order, kind: "sale",
                        entry_date: order.paid_at.to_date, cash_date: order.paid_at.to_date,
                        memo: "Ticket order #{order.code}", lines: sale_lines(order))
  end

  # Seats count as free again once a hold runs out; this order's own tickets
  # are still "reserved", so check the room without them.
  def self.seats_still_free?(order)
    requests = order.tickets.includes(:ticket_tier).group_by(&:ticket_tier).transform_values(&:size)
    order.ticket_listing.inventory.fits?(requests)
  end

  def self.ensure_seats_still_free!(order)
    raise SeatsGone unless seats_still_free?(order)
  end

  def self.refund_late_payment!(order, payment_intent_id)
    intent_id = payment_intent_id || order.stripe_payment_intent_id
    Stripe::Refund.create({ payment_intent: intent_id }, { idempotency_key: "ticket-late-refund-#{order.id}" }) if intent_id
    order.update!(status: "canceled", canceled_at: Time.current, stripe_payment_intent_id: intent_id)
    order.tickets.update_all(status: "void", updated_at: Time.current)
    Rails.logger.warn("[TicketOrderSettlement] order #{order.id} paid after its seats were gone; refunded")
  end

  private_class_method :post_money!, :ensure_seats_still_free!, :refund_late_payment!
end

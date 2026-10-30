# frozen_string_literal: true

# A gift certificate paying at checkout (TicketGiftCertificate). The
# certificate is payment, not a discount: the checkout's total, tax and fees
# are what they'd be with a card; the certificate covers as much of the total
# as it has, and the card pays the rest (TicketPurchase#card_cents).
#
# Its money is held the way seats are: applying a code draws the amount off
# the certificate at once (a held redemption), so two checkouts can't spend
# the same dollars; paying turns the hold into a redemption, and a hold that
# runs out, or a code the buyer removes, puts the money back. A refund puts
# its share back on the certificate rather than on a card.
#
# What a certificate pays never reaches the organization's CocoScout balance
# (they took that money when they sold the certificate, outside CocoScout):
# only the card's part does, so an order's balance credit is org_net less
# gift_certificate_cents, and the books carry the rest against "Gift
# certificates outstanding". Card processing is charged on what the card
# pays, nothing when it pays nothing; our 50¢ a ticket stands either way.
class TicketGiftCertificates
  class Error < StandardError; end
  # At settlement the held money is gone (a late payment after the hold ran
  # out, and someone else spent the certificate meanwhile).
  class Gone < StandardError; end

  WRONG_CODE = "That code isn't right. Check it against the certificate and try again."

  # The buyer typed a code on the checkout page. payable: the checkout
  # (TicketPurchase) or, for an order from before checkouts, the order.
  def self.apply!(payable, code)
    raise Error, "This order can't be changed anymore." unless payable.pending? && !payable.hold_expired?
    raise Error, "There's nothing left to pay." unless payable.total_cents.positive?
    raise Error, "A gift certificate can't pay for a pass yet." if payable.is_a?(TicketPurchase) && payable.ticket_pass_holdings.exists?

    certificate = find_for!(payable, code)
    ActiveRecord::Base.transaction do
      release!(payable) if payable.ticket_gift_certificate_id
      certificate.lock!
      raise Error, WRONG_CODE unless certificate.usable?

      amount = [ certificate.remaining_cents, payable.total_cents ].min
      certificate.update!(remaining_cents: certificate.remaining_cents - amount)
      certificate.redemptions.create!(amount_cents: amount, status: "held", **owner(payable))
      payable.update!(ticket_gift_certificate: certificate, gift_certificate_cents: amount)
      share!(payable)
    end
    payable.reload
  end

  # The buyer took the code off again.
  def self.remove!(payable)
    raise Error, "This order can't be changed anymore." unless payable.pending? && !payable.hold_expired?

    ActiveRecord::Base.transaction do
      release!(payable)
      payable.update!(ticket_gift_certificate: nil, gift_certificate_cents: 0)
      share!(payable)
    end
    payable.reload
  end

  # The checkout was repriced (a product added, a deal taken): what's held
  # follows the new total, as far as the certificate goes.
  def self.refresh!(payable)
    return unless payable.ticket_gift_certificate_id

    ActiveRecord::Base.transaction do
      certificate = payable.ticket_gift_certificate.lock!
      redemption = held_redemption(payable)
      held = redemption&.amount_cents.to_i
      want = [ certificate.remaining_cents + held, payable.total_cents ].min
      if redemption && want != held
        certificate.update!(remaining_cents: certificate.remaining_cents + held - want)
        redemption.update!(amount_cents: want)
      end
      payable.update!(gift_certificate_cents: redemption ? want : payable.gift_certificate_cents) if redemption
      share!(payable)
    end
  end

  # The hold ran out, or the checkout was swapped or canceled: the money
  # goes back on the certificate. The checkout keeps what it would have
  # paid, so a payment that still arrives is checked against the right
  # amount (and redeem! takes the money again if it's still there).
  def self.release!(payable)
    redemption = held_redemption(payable)
    return unless redemption

    ActiveRecord::Base.transaction do
      certificate = redemption.ticket_gift_certificate.lock!
      certificate.update!(remaining_cents: certificate.remaining_cents + redemption.amount_cents)
      redemption.update!(status: "released")
    end
  end

  # Holds that ran out, in one sweep (ExpireTicketHoldsJob).
  def self.release_stale!(at = Time.current)
    TicketGiftCertificateRedemption.held.where(ticket_purchase_id: TicketPurchase.stale(at).select(:id)).includes(:ticket_purchase).find_each do |r|
      release!(r.ticket_purchase)
    end
    TicketGiftCertificateRedemption.held.where(ticket_purchase_id: nil, ticket_order_id: TicketOrder.stale(at).select(:id)).includes(:ticket_order).find_each do |r|
      release!(r.ticket_order)
    end
  end

  # The checkout is paid: the held money is spent for good. Idempotent. A
  # hold that was released (a late payment) takes the money again if the
  # certificate still has it, and raises Gone if it doesn't.
  def self.redeem!(payable)
    return if payable.gift_certificate_cents.to_i.zero?

    redemption = payable.is_a?(TicketPurchase) ? payable.ticket_gift_certificate_redemptions.where(status: %w[held released redeemed]).order(:id).last
                                                : TicketGiftCertificateRedemption.where(ticket_order: payable, ticket_purchase_id: nil, status: %w[held released redeemed]).order(:id).last
    return if redemption.nil? || redemption.status == "redeemed"

    ActiveRecord::Base.transaction do
      certificate = redemption.ticket_gift_certificate.lock!
      if redemption.status == "released"
        raise Gone if certificate.voided? || certificate.remaining_cents < redemption.amount_cents

        certificate.update!(remaining_cents: certificate.remaining_cents - redemption.amount_cents)
      end
      redemption.update!(status: "redeemed")
    end
  end

  # A refund's share goes back on the certificate (TicketOrderRefund).
  def self.refund!(order, refund, cents)
    return unless cents.positive? && order.ticket_gift_certificate

    ActiveRecord::Base.transaction do
      certificate = order.ticket_gift_certificate.lock!
      certificate.update!(remaining_cents: certificate.remaining_cents + cents)
      certificate.redemptions.create!(amount_cents: cents, status: "refunded", ticket_order: order, ticket_purchase: order.ticket_purchase, ticket_refund: refund)
    end
  end

  # How much of a refund of `amount` goes back on the certificate: the
  # certificate's part first, up to what it paid of this order and hasn't
  # had back yet; the card gets whatever's left.
  def self.refund_share_cents(order, amount_cents)
    paid = order.gift_certificate_cents.to_i
    return 0 unless paid.positive?

    returned = order.ticket_refunds.succeeded.sum(:gift_certificate_cents)
    [ paid - returned, amount_cents, 0 ].sort[1]
  end

  # The checkout's certificate money, shared onto its shows' orders in
  # proportion to their totals, and every order's processing redone on what
  # the card pays (nothing when it pays nothing). With no certificate it
  # restores what TicketPricing quoted.
  def self.share!(payable)
    orders = payable.is_a?(TicketPurchase) ? payable.ticket_orders.to_a : [ payable ]
    return if orders.empty?

    gift = payable.gift_certificate_cents.to_i
    total = orders.sum(&:total_cents)
    card = total - gift
    in_person = orders.any? { |order| order.channel == "door_tap" }
    processing_total = if card.zero? || orders.first.money_path != "cocoscout"
      0
    else
      TicketPricing.processing_cents(card, in_person: in_person)
    end
    gifts = TicketPricing.share(gift, orders.map(&:total_cents))
    processing = TicketPricing.share(processing_total, orders.map { |o| o.subtotal_cents - o.discount_cents + o.tax_cents })
    ActiveRecord::Base.transaction do
      orders.each_with_index do |order, index|
        order.update!(ticket_gift_certificate_id: payable.ticket_gift_certificate_id, gift_certificate_cents: gifts[index],
                      processing_cents: processing[index],
                      org_net_cents: order.total_cents - processing[index] - order.platform_fee_cents)
      end
      if payable.is_a?(TicketPurchase)
        payable.update!(processing_cents: orders.sum(&:processing_cents) + payable.ticket_pass_holdings.sum(:processing_cents),
                        org_net_cents: orders.sum(&:org_net_cents) + payable.ticket_pass_holdings.sum(:org_net_cents))
      end
    end
  end

  # The code's certificate, when it's good for every show in the checkout.
  # A code that doesn't exist, is spent or was voided all get one answer, so
  # a guesser learns nothing; a real code on the wrong show is told where it
  # does work, since whoever holds it already knows it.
  def self.find_for!(payable, code)
    normalized = TicketGiftCertificate.normalize_code(code)
    certificate = payable.organization.ticket_gift_certificates.find_by(code: normalized)
    raise Error, WRONG_CODE unless certificate&.usable?

    listings = (payable.is_a?(TicketPurchase) ? payable.ticket_orders.map(&:ticket_listing) : [ payable.ticket_listing ]).uniq
    outside = listings.reject { |listing| certificate.covers?(listing) }
    if outside.any?
      raise Error, "This certificate is good for #{certificate.production_names.to_sentence}, not #{outside.map(&:display_title).uniq.to_sentence}."
    end

    certificate
  end

  def self.held_redemption(payable)
    if payable.is_a?(TicketPurchase)
      payable.ticket_gift_certificate_redemptions.held.order(:id).last
    else
      TicketGiftCertificateRedemption.held.where(ticket_order: payable, ticket_purchase_id: nil).order(:id).last
    end
  end

  def self.owner(payable)
    payable.is_a?(TicketPurchase) ? { ticket_purchase: payable, ticket_order: payable.primary_order } : { ticket_order: payable }
  end

  private_class_method :find_for!, :held_redemption, :owner
end

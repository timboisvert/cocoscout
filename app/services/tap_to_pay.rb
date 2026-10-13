# frozen_string_literal: true

# Tap to Pay at the door: the buyer taps their card or phone on the door
# phone, and Stripe Terminal (the Stripe Terminal SDK in the CocoScout app)
# charges it as an in-person payment. The server side of it:
#
#   - a Terminal Location for the organization (Stripe wants one per place
#     cards are taken; the venue's address), made once (location_for);
#   - a connection token the app uses to talk to Terminal (connection_token);
#   - the sale: the seats held like a card-or-phone sale (TicketCheckout),
#     and a card_present PaymentIntent for the order's total, at the
#     in-person rate (TicketPricing in_person) — the app collects and
#     confirms it (start!);
#   - the settlement when the app says it's paid, checked against Stripe,
#     through TicketOrderSettlement like every other sale: the organization's
#     balance gets its net, the books their lines, the tickets are checked in
#     (settle!). Stripe's webhook settles it too if the app never gets to.
#
# The money path is CocoScout's own Stripe account, exactly like online and
# card-or-phone sales, so the money check (Stripe = Σ OrgCashEntry +
# Σ CocoScoutLedgerEntry) holds with nothing new.
class TapToPay
  class Error < StandardError; end

  # Stripe's Terminal Location for the organization, made from its default
  # venue's address the first time. Tap to Pay needs an address to sell from.
  def self.location_for(organization)
    return organization.stripe_terminal_location_id if organization.stripe_terminal_location_id.present?

    venue = organization.locations.find_by(default: true) || organization.locations.where.not(address1: [ nil, "" ]).first
    if venue.nil? || venue.address1.blank? || venue.city.blank? || venue.state.blank? || venue.postal_code.blank?
      raise Error, "Tap to Pay needs the venue's address first — add it to a location in Manage → Settings → Locations."
    end

    location = Stripe::Terminal::Location.create(
      display_name: organization.name.first(100),
      address: { line1: venue.address1, line2: venue.address2.presence, city: venue.city, state: venue.state,
                 postal_code: venue.postal_code, country: "US" }.compact,
      metadata: { organization_id: organization.id }
    )
    organization.update!(stripe_terminal_location_id: location.id)
    location.id
  end

  # The short-lived token the app's Terminal SDK connects with.
  def self.connection_token(organization)
    Stripe::Terminal::ConnectionToken.create(location: location_for(organization)).secret
  end

  # Hold the seats and make the PaymentIntent the phone will take the tap
  # for. Returns the pending order, its stripe_payment_intent_id set.
  def self.start!(listing:, quantities:, user:, products: {}, buyer_name: nil, client_ip: nil)
    location_id = location_for(listing.organization)
    order = TicketCheckout.start!(listing: listing, quantities: quantities, channel: "door_tap", at_door: true, client_ip: client_ip)
    order.update!(buyer_name: buyer_name.to_s.squish.presence, issued_by: user)
    TicketCheckout.set_items!(order, products) if products.values.any? { |v| v.to_i.positive? }
    raise Error, "A free ticket can't be tapped for; comp it instead." unless order.total_cents.positive?

    intent = Stripe::PaymentIntent.create(
      {
        amount: order.total_cents,
        currency: "usd",
        payment_method_types: [ "card_present" ],
        capture_method: "automatic",
        description: "#{listing.display_title} · #{listing.organization.name}".first(250),
        metadata: { type: "ticket_order", ticket_order_id: order.id, ticket_order_code: order.code,
                    organization_id: order.organization_id, ticket_listing_id: listing.id, door: "tap",
                    terminal_location: location_id },
        # Segregates each org's money flows Stripe-side, like the cash ledger.
        transfer_group: "org_#{order.organization_id}"
      },
      { idempotency_key: "ticket-order-#{order.id}-#{order.total_cents}-tap" }
    )
    order.update!(stripe_payment_intent_id: intent.id)
    order
  end

  # The intent's client secret, for the app to collect and confirm against.
  def self.client_secret(order)
    Stripe::PaymentIntent.retrieve(order.stripe_payment_intent_id).client_secret
  end

  # The app says the tap went through: ask Stripe, and settle the order the
  # way every paid order settles. Idempotent; the webhook may get there first.
  def self.settle!(order)
    return order if order.paid?
    raise Error, "This sale has no payment to check." if order.stripe_payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(order.stripe_payment_intent_id)
    unless intent.status == "succeeded"
      raise Error, "Stripe hasn't confirmed the payment yet (#{intent.status.to_s.humanize.downcase}). Try again in a moment."
    end

    TicketOrderSettlement.settle!(order, payment_intent_id: intent.id, charge_id: intent.latest_charge, amount_cents: intent.amount)
  end
end

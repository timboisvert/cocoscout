# frozen_string_literal: true

# Tap to Pay at the door: the buyer taps their card or phone on the door
# phone, and Stripe Terminal (the Stripe Terminal SDK in the CocoScout app)
# charges it as an in-person payment. The server side of it:
#
#   - a Terminal Location for the organization (Stripe wants one per place
#     cards are taken; the venue's address), made once (location_for);
#   - a connection token the app uses to talk to Terminal (connection_token);
#   - the sale: the seats held like a card-or-phone sale (TicketCheckout),
#     at the in-person rate (TicketPricing in_person) (start!), and what the
#     app makes the card_present PaymentIntent with, then collects and
#     confirms (payment_params);
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

  # Who sees Tap to Pay on iPhone (Apple's publishing review, 2026-10-19):
  # an organization with its box office open and Tap to Pay switched on
  # (TicketingProfile#tap_to_pay, off until Apple grants the publishing
  # entitlement), and, there, the people who can sell at the door.
  def self.available_for?(organization)
    profile = organization&.ticketing_profile
    profile.present? && profile.enabled? && profile.tap_to_pay?
  end

  # Whether the organization sees Tap to Pay on iPhone on Ticketing settings
  # → Door, to switch it on or off: CocoScout's to offer while it's new
  # (TicketingProfile#tap_to_pay_offered, Tim 2026-10-19). A superadmin sees
  # it everywhere, to offer it.
  def self.offered_to?(organization, user = nil)
    profile = organization&.ticketing_profile
    return false if profile.nil?

    profile.tap_to_pay_offered? || profile.tap_to_pay? || user&.superadmin? || false
  end

  def self.organizations_for(user)
    TicketingDoorAccess.organizations_for(user).select do |organization|
      available_for?(organization) && TicketingDoorAccess.at_least?(TicketingDoorAccess.level_for(user, organization), :box_office)
    end
  end

  # Apple's terms are accepted once for CocoScout's payment account, the one
  # every organization's taps go through, so only CocoScout's administrators
  # may accept them (Apple 3.8); everyone else is asked to wait for that.
  def self.can_accept_terms?(user)
    user&.superadmin? || false
  end

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

  # Hold the seats for the tap. Returns the pending order. The app makes the
  # PaymentIntent itself with the Terminal SDK (payment_params): Stripe no
  # longer lets the server name card_present on this account (payment methods
  # are managed from the Dashboard since Oct 2026, and Payment method
  # configurations can't include in-person cards), so the SDK, which creates
  # in-person intents on its own, is the way in.
  def self.start!(listing:, quantities:, user:, products: {}, buyer_name: nil, client_ip: nil)
    location_for(listing.organization) # no venue address, no Tap to Pay: say so before holding seats
    order = TicketCheckout.start!(listing: listing, quantities: quantities, channel: "door_tap", at_door: true, client_ip: client_ip)
    order.update!(buyer_name: buyer_name.to_s.squish.presence, issued_by: user)
    TicketCheckout.set_items!(order, products) if products.values.any? { |v| v.to_i.positive? }
    raise Error, "A free ticket can't be tapped for; comp it instead." unless order.total_cents.positive?

    order
  end

  # What the app makes the PaymentIntent with: the order's total, and the
  # metadata Stripe's webhook and the books find the order by.
  def self.payment_params(order)
    listing = order.ticket_listing
    {
      amount_cents: order.total_cents,
      currency: "usd",
      description: "#{listing.display_title} · #{listing.organization.name}".first(250),
      metadata: { type: "ticket_order", ticket_order_id: order.id, ticket_order_code: order.code,
                  organization_id: order.organization_id, ticket_listing_id: listing.id, door: "tap",
                  terminal_location: location_for(listing.organization) }.transform_values(&:to_s),
      # Segregates each org's money flows Stripe-side, like the cash ledger.
      transfer_group: "org_#{order.organization_id}"
    }
  end

  # The app says the tap went through, with the PaymentIntent it made: ask
  # Stripe, and settle the order the way every paid order settles (which
  # checks the amount). Idempotent; the webhook may get there first.
  def self.settle!(order, payment_intent_id: nil)
    return order if order.paid?

    intent_id = payment_intent_id.presence || order.stripe_payment_intent_id
    raise Error, "This sale has no payment to check." if intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(intent_id)
    raise Error, "That payment isn't for this sale." unless intent.metadata&.[]("ticket_order_id").to_s == order.id.to_s
    unless intent.status == "succeeded"
      raise Error, "Our payment provider hasn't confirmed the payment yet (#{intent.status.to_s.humanize.downcase}). Try again in a moment."
    end

    # A payment for the wrong amount is refunded there and the sale canceled.
    TicketOrderSettlement.settle!(order, payment_intent_id: intent.id, charge_id: intent.latest_charge, amount_cents: intent.amount)
    unless order.reload.paid?
      raise Error, "The card was charged #{format('$%.2f', intent.amount / 100.0)}, not this sale's total, so it was refunded and nobody was checked in. Start the sale again."
    end

    order
  end
end

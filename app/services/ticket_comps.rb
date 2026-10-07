# frozen_string_literal: true

# Giving tickets away: a manager names the people (or pastes a guest list),
# picks a ticket type, and each person gets a real order — free, no card, no
# fees — with the normal email and QR codes. Comps take seats like any other
# ticket, so a full show says so. All of them are given, or none.
class TicketComps
  class Error < StandardError; end

  Guest = Data.define(:name, :email, :tier, :quantity)

  # "Name, email, 2" per line; email and count optional ("Name" alone is one
  # ticket with no email). A trailing part that names a ticket type picks it.
  def self.parse(text, listing:, default_tier:)
    tiers = listing.ticket_tiers.active.to_a
    text.to_s.lines.filter_map do |line|
      parts = line.split(/[,\t]/).map(&:strip).reject(&:empty?)
      next if parts.empty?

      name = parts.shift
      email = parts.find { |p| p.include?("@") }
      count = parts.find { |p| p.match?(/\A\d+\z/) }
      tier = tiers.find { |t| parts.any? { |p| p.casecmp?(t.name) } } || default_tier
      Guest.new(name: name, email: email&.downcase, tier: tier, quantity: (count || 1).to_i)
    end
  end

  def self.give!(listing, guests, by:, note: nil, email_them: true)
    raise Error, "Add at least one person." if guests.empty?
    raise Error, "This show was canceled." if listing.status == "canceled" || listing.show.canceled

    bad = guests.find { |g| g.name.blank? || g.quantity.to_i < 1 || g.tier.nil? || (g.email.present? && !g.email.match?(URI::MailTo::EMAIL_REGEXP)) }
    raise Error, "Check #{bad.name.presence || 'each row'}: every person needs a name, a ticket type and a count, and a valid email if there is one." if bad

    requests = TicketCheckout.seat_requests(guests.group_by(&:tier).transform_values { |gs| gs.sum(&:quantity) })
    orders = []
    Ticketing::Inventory.reserve!(listing, requests) do
      guests.each do |guest|
        order = TicketOrder.create!(organization: listing.organization, ticket_listing: listing, status: "paid", paid_at: Time.current,
                                    channel: "comp", money_path: "none", fee_mode: listing.effective_fee_mode,
                                    buyer_name: guest.name.squish, buyer_email: guest.email.presence,
                                    issued_by: by, note: note.to_s.squish.presence)
        # A 4-pack given is four tickets, one per person.
        guest.quantity.times do
          guest.tier.seat_prices.each do |cents|
            order.tickets.create!(ticket_tier: guest.tier.base_tier, bundle_tier: (guest.tier if guest.tier.bundle?), ticket_listing: listing,
                                  status: "valid", price_cents: cents, discount_cents: cents)
          end
        end
        TicketCheckout.price!(order)
        orders << order
      end
    end

    orders.each { |order| TicketOrderConfirmationJob.perform_later(order.id) if email_them && order.buyer_email.present? }
    TicketingAfterSaleJob.perform_later(orders.last.id)
    orders
  rescue Ticketing::Inventory::SoldOut
    raise Error, sold_out_message(listing, requests)
  end

  # Which type ran short, and where its seats went: "Front Row VIP has no
  # seats left: 3 sold here, 9 on Ticket Tailor."
  def self.sold_out_message(listing, requests)
    inventory = Ticketing::Inventory.new(listing)
    tier, = (requests || {}).find { |t, seats| (left = inventory.remaining(tier: t)) && left < seats }
    return "That's more than the seats left. Raise the seats on the show if the room has space." unless tier

    left = inventory.remaining(tier: tier)
    return "#{tier.name} has only #{left} #{left == 1 ? 'seat' : 'seats'} left." if left.positive?

    where = [ ("#{inventory.sold(tier: tier)} sold here" if inventory.sold(tier: tier).positive?), inventory.outside_words(tier: tier).presence ].compact
    "#{tier.name} has no seats left#{": #{where.to_sentence}" if where.any?}. Raise its seats if the room has space."
  end
end

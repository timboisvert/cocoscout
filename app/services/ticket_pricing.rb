# frozen_string_literal: true

# What a ticket order costs and where every cent goes.
#
# CocoScout keeps 50¢ per paid ticket. Card processing (2.9% + 30¢) passes
# through at cost, charged once per ORDER, so a pair costs less per ticket
# than a single. One switch decides who covers both:
#
#   buyer pays fees  — the total is grossed up so the theater nets exactly the
#                      ticket price: one $20 ticket → buyer pays $21.42.
#   theater absorbs  — the buyer pays the ticket price; the theater nets it
#                      less our 50¢ and processing: $20 → $18.62.
#
# Tax added on top is part of what's charged (and what Stripe's 2.9% is taken
# on) but belongs to the theater, who remits it. Cash at the door and comps
# carry no fees at all. All integer cents; no floats touch money.
class TicketPricing
  PLATFORM_FEE_CENTS = 50
  PROCESSING_PER_MILLE = 29 # 2.9%
  PROCESSING_FIXED_CENTS = 30

  Quote = Data.define(:subtotal_cents, :discount_cents, :tax_cents, :platform_fee_cents,
                      :processing_cents, :buyer_fee_cents, :total_cents, :org_net_cents, :paid_ticket_count)

  # items: one hash per ticket — { price_cents:, discount_cents:, tax_cents: },
  # where tax_cents is tax ADDED on top (tax included in a price is already
  # inside price_cents). A product bought with the tickets is an item with
  # platform_fee: false: our 50¢ is per paid ticket, and processing is per
  # order, so a product only adds its price, its tax and the 2.9% on them.
  def self.quote(items:, fee_mode:, money_path: "cocoscout")
    subtotal = items.sum { |i| i[:price_cents].to_i }
    discount = items.sum { |i| i[:discount_cents].to_i }
    tax = items.sum { |i| i[:tax_cents].to_i }
    paid = items.count { |i| i[:platform_fee] != false && i[:price_cents].to_i - i[:discount_cents].to_i > 0 }
    base = subtotal - discount + tax

    if money_path != "cocoscout" || base.zero?
      return Quote.new(subtotal_cents: subtotal, discount_cents: discount, tax_cents: tax, platform_fee_cents: 0,
                       processing_cents: 0, buyer_fee_cents: 0, total_cents: base, org_net_cents: base,
                       paid_ticket_count: paid)
    end

    platform = PLATFORM_FEE_CENTS * paid
    total = fee_mode == "buyer" ? gross_up(base + platform) : base
    processing = processing_cents(total)

    Quote.new(subtotal_cents: subtotal, discount_cents: discount, tax_cents: tax, platform_fee_cents: platform,
              processing_cents: processing, buyer_fee_cents: total - base, total_cents: total,
              org_net_cents: total - processing - platform, paid_ticket_count: paid)
  end

  # Cents shared across parts in proportion to their weights, the leftover
  # cents going to the largest remainders, so the parts always add up: how a
  # purchase's processing and buyer-paid fees land on each show's order.
  def self.share(cents, weights)
    return [] if weights.empty?

    total = weights.sum
    return [ cents ] + Array.new(weights.size - 1, 0) if total.zero?

    exact = weights.map { |weight| Rational(cents * weight, total) }
    parts = exact.map(&:floor)
    order = exact.each_with_index.sort_by { |value, index| [ -(value - value.floor), index ] }.map(&:last)
    order.first(cents - parts.sum).each { |index| parts[index] += 1 }
    parts
  end

  # Stripe's cut of a charge, rounded half up.
  def self.processing_cents(total_cents)
    ((total_cents * PROCESSING_PER_MILLE) + 500) / 1000 + PROCESSING_FIXED_CENTS
  end

  # The smallest charge that leaves exactly `needed` after processing.
  # (total − processing) climbs by 0 or 1 cent per cent of total, so the first
  # total that reaches `needed` hits it exactly.
  def self.gross_up(needed_cents)
    total = (((needed_cents + PROCESSING_FIXED_CENTS) * 1000) / (1000 - PROCESSING_PER_MILLE)) - 2
    total += 1 while total - processing_cents(total) < needed_cents
    total
  end

  # What one ticket of a tier really costs a buyer: fees in, and tax in too
  # when it's added on top — the one number every page shows. A bigger order
  # can only cost less per ticket (processing's 30¢ is charged once), so the
  # total at checkout is never more than the prices added up. (The FTC rule
  # requires fees in the price; including tax as well means no surprise.)
  # A type that admits several people (a 4-pack) is priced as its tickets
  # together: 50¢ for each person, processing once.
  def self.all_in_price_cents(listing, tier)
    items = tier.seat_prices.map do |cents|
      { price_cents: cents, discount_cents: 0, tax_cents: TaxCalculator.for_ticket(listing, tier.base_tier, cents).added_cents }
    end
    quote(items: items, fee_mode: listing.effective_fee_mode).total_cents
  end

  # What one product really adds for a buyer, fees and tax in, by the same
  # rule: shown on its own it can only overstate what it adds to an order
  # (processing's 30¢ is already in the tickets' price), never understate.
  def self.all_in_product_price_cents(listing, offer)
    tax = TaxCalculator.for_product(listing, offer, offer.price_cents).added_cents
    quote(items: [ { price_cents: offer.price_cents, discount_cents: 0, tax_cents: tax, platform_fee: false } ],
          fee_mode: listing.effective_fee_mode).total_cents
  end
end

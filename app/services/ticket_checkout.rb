# frozen_string_literal: true

# A buyer starting an order on a ticket page: check the tickets are on sale
# and the seats are there, hold them for ten minutes, and price everything —
# discount, tax, our fee and card processing (TicketPricing). Paying turns the
# held tickets into real ones (TicketOrderSettlement); an unpaid hold simply
# runs out and the seats go back.
#
# A buyer who goes back from checkout keeps their hold: asking again for the
# same tickets (replacing: the held order's token) reopens the same order and
# clock, and asking for different ones swaps the old hold for a new one in a
# single transaction, so a new hold that doesn't fit leaves the old one be.
class TicketCheckout
  class Error < StandardError; end

  # quantities: { tier_id => count } (a count of purchases: a 4-pack counts
  # once and becomes four tickets). code: a discount code, or the code that
  # unlocks a hidden tier. replacing: the token of this buyer's live hold.
  # at_door: the door selling to someone in front of them, which works after
  # online sales close and with any ticket type still on the show. via: the
  # short link code the buyer arrived through (the cs_via cookie), remembered
  # on the order so the Links page can say what each link sold.
  def self.start!(listing:, quantities:, code: nil, channel: "online", client_ip: nil, referrer: nil, replacing: nil, at_door: false, via: nil)
    if at_door
      raise Error, "This show was canceled." if listing.status == "canceled" || listing.show.canceled
    else
      raise Error, "Tickets aren't on sale for this show right now." unless listing.selling?
    end

    code = code.to_s.strip.upcase.presence
    requests = requested_tiers(listing, quantities, code, at_door: at_door)
    seats = seat_requests(requests)
    max = listing.effective_max_per_order
    raise Error, "You can buy up to #{max} tickets at a time." if seats.values.sum > max

    discount = code && find_discount(listing, code)
    raise Error, "That code doesn't work for this show." if code && discount.nil? && requests.keys.none?(&:hidden?)

    held = replacing.present? ? listing.ticket_orders.holding.find_by(token: replacing.to_s) : nil
    return held if held && same_request?(held, requests, discount)

    short_link = via.present? ? ShortLink.live.where(organization: listing.organization).find_by(code: via.to_s.strip.upcase) : nil
    order = nil
    ActiveRecord::Base.transaction do
      # Expiring it now frees its seats for the new hold (Inventory ignores a
      # lapsed hold), and anything else in its checkout goes with it; a
      # SoldOut below rolls this back too.
      held&.ticket_purchase ? held.ticket_purchase.expire! : held&.update!(status: "expired", expires_at: Time.current)
      Ticketing::Inventory.reserve!(listing, seats) do
        expires_at = TicketOrder::HOLD.from_now
        purchase = TicketPurchase.create!(organization: listing.organization, channel: channel, expires_at: expires_at)
        order = TicketOrder.create!(organization: listing.organization, ticket_listing: listing, status: "pending",
                                    ticket_purchase: purchase,
                                    channel: channel, money_path: "cocoscout", fee_mode: listing.effective_fee_mode,
                                    expires_at: expires_at, ticket_discount_code: discount,
                                    client_ip: client_ip, referrer: referrer.to_s.first(500).presence,
                                    short_link: short_link, utm: short_link ? { "via" => short_link.code } : {})
        requests.each { |tier, count| count.times { add_purchase(order, tier, discount) } }
        # Products added on the old hold come along to the new one.
        set_items!(order, held_item_quantities(held), reprice: false) if held
        price!(order)
      end
    end
    order
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, there aren't enough seats left for that. Try fewer tickets."
  end

  # A buyer starting on a pass: a seat at every show in it for each pass,
  # held together for ten minutes in one checkout (one order per show, one
  # payment), every ticket carrying its show's share of the pass price. A
  # show without the seats stops the whole pass; nothing is held.
  def self.start_pass!(pass:, quantity:, client_ip: nil, referrer: nil, via: nil)
    rows = pass.rows
    raise Error, "This pass isn't on sale right now." unless pass.selling?(Time.current, rows)

    quantity = quantity.to_i
    raise Error, "Pick at least one pass." unless quantity.positive?
    max = pass.effective_max_per_order(rows)
    raise Error, "You can buy up to #{max} passes at a time." if max && quantity > max
    if pass.max_sold && quantity > pass.max_sold - pass.sold_count(rows)
      raise Error, "Sorry, there aren't that many passes left."
    end

    shares = pass.shares(rows)
    fee_mode = pass.fee_mode(rows)
    short_link = via.present? ? ShortLink.live.where(organization: pass.organization).find_by(code: via.to_s.strip.upcase) : nil
    orders = []
    ActiveRecord::Base.transaction do
      # Shows locked in one order, so two buyers' passes can't deadlock.
      reserve_all!(rows.sort_by(&:ticket_listing_id), quantity) do
        expires_at = TicketOrder::HOLD.from_now
        purchase = TicketPurchase.create!(organization: pass.organization, channel: "online", expires_at: expires_at)
        rows.each_with_index do |row, index|
          order = TicketOrder.create!(organization: pass.organization, ticket_listing: row.ticket_listing, ticket_purchase: purchase,
                                      status: "pending", channel: "online", money_path: "cocoscout", fee_mode: fee_mode,
                                      expires_at: expires_at, client_ip: client_ip, referrer: referrer.to_s.first(500).presence,
                                      short_link: short_link, utm: short_link ? { "via" => short_link.code } : {})
          # The regular price, less the pass's saving; a share above the
          # regular price is simply the price.
          price = [ row.ticket_tier.price_cents, shares[index] ].max
          quantity.times { add_ticket(order, row.ticket_tier, price, price - shares[index], pass: pass) }
          orders << order
        end
        purchase.price!
      end
    end
    orders.first.reload
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, one of the shows in this pass doesn't have enough seats left. Try fewer passes."
  end

  # Holds each show's seats under its own lock, one after another, and runs
  # the block once every show has them.
  def self.reserve_all!(rows, quantity, &block)
    return yield if rows.empty?

    row, *rest = rows
    Ticketing::Inventory.reserve!(row.ticket_listing, { row.ticket_tier => quantity }) { reserve_all!(rest, quantity, &block) }
  end

  # A live hold's purchases by type: { tier_id => count } (a held bundle is
  # several tickets and counts once), as the show's page steppers count them.
  def self.held_quantities(order)
    counts = order.tickets.group(Arel.sql("COALESCE(bundle_tier_id, ticket_tier_id)")).count
    admits = TicketTier.where(id: counts.keys).pluck(:id, :admits).to_h
    counts.to_h { |tier_id, tickets| [ tier_id, tickets / [ admits[tier_id].to_i, 1 ].max ] }
  end

  # Seats a request takes, on the types that hold them: { tier => people }.
  # A bundle's people take its type's seats.
  def self.seat_requests(requests)
    requests.each_with_object(Hash.new(0)) do |(tier, count), seats|
      seats[tier.base_tier] += count * tier.admits.to_i.clamp(1, 20)
    end
  end

  def self.same_request?(order, requests, discount)
    held_quantities(order) == requests.to_h { |tier, count| [ tier.id, count ] } &&
      order.ticket_discount_code_id == discount&.id
  end

  # Products on a hold: { product_id => count } from the checkout page's
  # steppers, replacing what was there. Only products the date offers, only
  # while the order is still being paid for. Each line snapshots the offer
  # (name, price, revenue rule) and records its tax, like a ticket.
  def self.set_items!(order, quantities, reprice: true)
    raise Error, "This order can't be changed anymore." unless order.pending?

    listing = order.ticket_listing
    offers = listing.product_offers(at_door: order.channel.start_with?("door_")).index_by(&:id)
    wanted = quantities.to_h.filter_map { |id, count|
      count = count.to_i.clamp(0, MAX_PER_PRODUCT)
      [ id.to_i, count ] if count.positive? && offers.key?(id.to_i)
    }.to_h

    order.transaction do
      order.ticket_order_items.where.not(ticket_product_id: wanted.keys).destroy_all
      wanted.each do |product_id, count|
        offer = offers.fetch(product_id)
        item = order.ticket_order_items.find_or_initialize_by(ticket_product_id: product_id)
        next if item.persisted? && item.quantity == count && item.unit_price_cents == offer.price_cents

        item.assign_attributes(organization_id: order.organization_id, ticket_listing: listing, status: "reserved",
                               name: offer.name, description: offer.description, unit_price_cents: offer.price_cents,
                               quantity: count, counts_toward_ticket_revenue: offer.counts_toward_ticket_revenue)
        item.save!
        item.tax_lines.delete_all
        record_item_tax(order, item, offer)
      end
      price!(order) if reprice
    end
    order
  end

  # A buyer can add this many of one product to an order.
  MAX_PER_PRODUCT = 10

  # The deals a checkout can add (TicketOffer): [[offer, listing, tier]], one
  # per other show, soonest first, at most three. Only on a plain ticket
  # checkout bought online (a pass is its own deal).
  def self.deals_for(order)
    purchase = order.ticket_purchase
    return [] unless purchase && order.channel == "online" && order.tickets.none? { |t| t.ticket_pass_id || t.ticket_offer_id }

    others = purchase.ticket_orders.reject { |o| o.id == order.id }.index_by(&:ticket_listing_id)
    TicketOffer.live.where(organization_id: order.organization_id).includes(:target_tier).to_a
               .select { |offer| offer.triggers_on?(order.ticket_listing) }
               .filter_map { |offer| (target = offer.target_for(order.ticket_listing)) && [ offer, *target ] }
               .reject { |offer, listing, _| others[listing.id] && others[listing.id].tickets.none? { |t| t.ticket_offer_id == offer.id } }
               .uniq { |_, listing, _| listing.id }
               .sort_by { |_, listing, _| listing.starts_at || Time.current }
               .first(3)
  end

  # Deals still open to a buyer after they've paid (TicketOffer
  # #after_purchase_days), with room left for this order: [[offer, listing,
  # tier]], like deals_for.
  def self.deals_after(order, at = Time.current)
    purchase = order.ticket_purchase
    return [] unless purchase && order.paid? && order.channel == "online" && order.paid_at &&
                     order.tickets.none? { |t| t.ticket_pass_id || t.ticket_offer_id }

    in_purchase = purchase.ticket_orders.map(&:ticket_listing_id)
    TicketOffer.live.where(organization_id: order.organization_id).includes(:target_tier).to_a
               .select { |offer| offer.after_purchase_days.positive? && order.paid_at > offer.after_purchase_days.days.ago && offer.triggers_on?(order.ticket_listing, at) }
               .filter_map { |offer| (target = offer.target_for(order.ticket_listing)) && [ offer, *target ] }
               .reject { |_, listing, _| in_purchase.include?(listing.id) }
               .uniq { |_, listing, _| listing.id }
               .select { |offer, _, _| deal_room(order, offer).positive? }
               .sort_by { |_, listing, _| listing.starts_at || Time.current }
               .first(3)
  end

  # How many more of a deal an order's tickets can still earn: one per
  # ticket (or the deal's own number), less what this checkout and any
  # opened from it already took.
  def self.deal_room(order, offer)
    bought = order.tickets.where(status: Ticket::SOLD_STATUSES, ticket_offer_id: nil).count
    purchases = [ order.ticket_purchase_id, *TicketPurchase.where(earned_by_purchase_id: order.ticket_purchase_id).where.not(status: %w[expired canceled]).pluck(:id) ]
    taken = Ticket.joins(:ticket_order).where(ticket_orders: { ticket_purchase_id: purchases }, ticket_offer_id: offer.id)
                  .where(status: Ticket::SOLD_STATUSES + %w[reserved]).count
    offer.limit_for(bought) - taken
  end

  # A buyer taking a deal after they've paid: a new checkout for the other
  # show at the deal price, remembering the purchase that earned it, with
  # their details already in.
  def self.start_deal!(order:, offer:, quantity:)
    match = deals_after(order).find { |candidate, _, _| candidate.id == offer.id }
    raise Error, "That deal isn't available anymore." unless match

    _, listing, tier = match
    quantity = quantity.to_i
    room = deal_room(order, offer)
    raise Error, "Pick how many." unless quantity.positive?
    raise Error, "You can add up to #{room} with your tickets." if quantity > room

    new_order = nil
    ActiveRecord::Base.transaction do
      Ticketing::Inventory.reserve!(listing, { tier => quantity }) do
        expires_at = TicketOrder::HOLD.from_now
        purchase = TicketPurchase.create!(organization: order.organization, channel: "online", expires_at: expires_at,
                                          earned_by_purchase: order.ticket_purchase)
        new_order = TicketOrder.create!(organization: order.organization, ticket_listing: listing, ticket_purchase: purchase,
                                        status: "pending", channel: "online", money_path: "cocoscout", fee_mode: listing.effective_fee_mode,
                                        expires_at: expires_at, buyer_name: order.buyer_name, buyer_email: order.buyer_email,
                                        buyer_phone: order.buyer_phone)
        price = offer.deal_price_cents(tier)
        quantity.times { add_ticket(new_order, tier, tier.price_cents, tier.price_cents - price, offer: offer) }
        purchase.price!
      end
    end
    new_order.reload
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, that show doesn't have enough seats left for that."
  end

  # The deals on a hold: { offer_id => count } from the checkout page's
  # steppers, replacing what was there. Each deal's tickets are the other
  # show's own, in its own order in the same checkout and on the same clock,
  # at the deal price; never more than the deal allows for the tickets
  # being bought.
  def self.set_deals!(order, quantities)
    raise Error, "This order can't be changed anymore." unless order.pending? && !order.hold_expired?

    purchase = order.ticket_purchase
    bought = order.tickets.count
    wanted_by_offer = quantities.to_h.transform_keys(&:to_s)
    deals_for(order).each do |offer, listing, tier|
      wanted = wanted_by_offer[offer.id.to_s].to_i.clamp(0, offer.limit_for(bought))
      existing = purchase.ticket_orders.find_by(ticket_listing_id: listing.id)
      next if wanted == (existing ? existing.tickets.where(ticket_offer_id: offer.id).count : 0)

      ActiveRecord::Base.transaction do
        if existing
          TaxLine.where(taxable_type: "Ticket", taxable_id: existing.tickets.select(:id)).delete_all
          existing.tickets.delete_all
        end
        if wanted.zero?
          existing&.destroy!
        else
          Ticketing::Inventory.reserve!(listing, { tier => wanted }) do
            deal_order = existing || TicketOrder.create!(organization: order.organization, ticket_listing: listing, ticket_purchase: purchase,
                                                         status: "pending", channel: order.channel, money_path: "cocoscout",
                                                         fee_mode: order.fee_mode, expires_at: order.expires_at, client_ip: order.client_ip)
            price = offer.deal_price_cents(tier)
            wanted.times { add_ticket(deal_order, tier, tier.price_cents, tier.price_cents - price, offer: offer) }
          end
        end
      end
    end
    purchase.price!
    order.reload
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, that show doesn't have enough seats left for that."
  end

  def self.held_item_quantities(order)
    order.ticket_order_items.pluck(:ticket_product_id, :quantity).to_h
  end

  # The order's numbers, from its tickets, its products and their tax. An
  # order in a checkout is priced with the rest of it (TicketPurchase#price!),
  # since card processing is charged once for the whole purchase.
  def self.price!(order)
    if order.ticket_purchase
      order.ticket_purchase.price!
      return order.reload
    end

    tickets = order.tickets.to_a
    products = order.ticket_order_items.to_a
    quote = TicketPricing.quote(items: order_items(order), fee_mode: order.fee_mode, money_path: order.money_path)
    order.update!(subtotal_cents: quote.subtotal_cents, discount_cents: quote.discount_cents,
                  tax_cents: tickets.sum(&:tax_cents) + products.sum(&:tax_cents), platform_fee_cents: quote.platform_fee_cents,
                  processing_cents: quote.processing_cents, buyer_fee_cents: quote.buyer_fee_cents,
                  total_cents: quote.total_cents, org_net_cents: quote.org_net_cents)
    order
  end

  # An order's tickets and products as TicketPricing items.
  def self.order_items(order)
    items = order.tickets.includes(:tax_lines).map do |ticket|
      { price_cents: ticket.price_cents, discount_cents: ticket.discount_cents,
        tax_cents: ticket.tax_lines.reject(&:included).sum(&:tax_cents) }
    end
    items + order.ticket_order_items.includes(:tax_lines).map do |item|
      { price_cents: item.price_cents, discount_cents: 0, platform_fee: false,
        tax_cents: item.tax_lines.reject(&:included).sum(&:tax_cents) }
    end
  end

  def self.record_item_tax(order, item, offer)
    listing = order.ticket_listing
    tax = TaxCalculator.for_product(listing, offer, item.price_cents)
    tax.lines.each do |line|
      TaxLine.create!(organization_id: order.organization_id, taxable: item, tax_rate: line.tax_rate,
                      name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                      included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                      base_cents: line.base_cents, tax_cents: line.tax_cents,
                      sale_date: Date.current, event_date: listing.starts_at&.to_date)
    end
    item.update_columns(tax_cents: tax.tax_cents)
  end

  # A code works when it's active, inside its dates and uses, and covers this
  # show (directly, through its production, or org-wide).
  def self.find_discount(listing, code)
    TicketDiscountCode.where(organization_id: listing.organization_id, code: code, active: true)
                      .detect { |discount| discount.applies_to?(listing) && discount.usable? }
  end

  def self.requested_tiers(listing, quantities, code, at_door: false)
    tiers = listing.ticket_tiers.active.select { |tier| at_door ? tier.available? : tier.selling? }.index_by(&:id)
    requests = {}
    quantities.to_h.each do |tier_id, count|
      count = count.to_i
      next unless count.positive?

      tier = tiers[tier_id.to_i]
      raise Error, "That ticket isn't on sale." if tier.nil? || (!at_door && tier.hidden? && tier.unlock_code != code)
      raise Error, "#{tier.name} tickets come at least #{tier.min_per_order} at a time." if count < tier.min_per_order
      raise Error, "#{tier.name} tickets come at most #{tier.max_per_order} at a time." if tier.max_per_order && count > tier.max_per_order

      requests[tier] = count
    end
    raise Error, "Pick at least one ticket." if requests.empty?

    requests
  end

  # One purchase held: one ticket per person it admits (a 4-pack is four
  # tickets sharing its price and its discount), each with its tax, recorded
  # now so the price the buyer is quoted is the price they pay, even if the
  # theater changes its tax rate while they're checking out.
  def self.add_purchase(order, tier, discount)
    listing = order.ticket_listing
    off = discount&.applies_to?(listing, tier) ? discount.discount_cents_for(tier.price_cents) : 0
    tier.seat_prices.zip(tier.seat_prices(off)).each { |price, seat_off| add_ticket(order, tier, price, seat_off) }
  end

  # One person's ticket: always of the type that holds the seat (a bundle's
  # tickets are its type's, remembering the bundle).
  def self.add_ticket(order, tier, price_cents, off, pass: nil, offer: nil)
    listing = order.ticket_listing
    ticket = order.tickets.create!(ticket_tier: tier.base_tier, bundle_tier: (tier if tier.bundle?), ticket_listing: listing,
                                   status: "reserved", price_cents: price_cents, discount_cents: off, ticket_pass: pass,
                                   ticket_offer: offer)
    tax = TaxCalculator.for_ticket(listing, tier.base_tier, price_cents - off)
    tax.lines.each do |line|
      TaxLine.create!(organization_id: order.organization_id, taxable: ticket, tax_rate: line.tax_rate,
                      name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                      included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                      base_cents: line.base_cents, tax_cents: line.tax_cents,
                      sale_date: Date.current, event_date: listing.starts_at&.to_date)
    end
    ticket.update_columns(tax_cents: tax.tax_cents)
  end

  private_class_method :requested_tiers, :add_purchase, :add_ticket, :same_request?, :held_item_quantities, :reserve_all!
end

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

  # quantities: { tier_id => count }. code: a discount code, or the code that
  # unlocks a hidden tier. replacing: the token of this buyer's live hold.
  # at_door: the door selling to someone in front of them, which works after
  # online sales close and with any ticket type still on the show.
  def self.start!(listing:, quantities:, code: nil, channel: "online", client_ip: nil, referrer: nil, replacing: nil, at_door: false)
    if at_door
      raise Error, "This show was canceled." if listing.status == "canceled" || listing.show.canceled
    else
      raise Error, "Tickets aren't on sale for this show right now." unless listing.selling?
    end

    code = code.to_s.strip.upcase.presence
    requests = requested_tiers(listing, quantities, code, at_door: at_door)
    max = listing.effective_max_per_order
    raise Error, "You can buy up to #{max} tickets at a time." if requests.values.sum > max

    discount = code && find_discount(listing, code)
    raise Error, "That code doesn't work for this show." if code && discount.nil? && requests.keys.none?(&:hidden?)

    held = replacing.present? ? listing.ticket_orders.holding.find_by(token: replacing.to_s) : nil
    return held if held && same_request?(held, requests, discount)

    order = nil
    ActiveRecord::Base.transaction do
      # Expiring it now frees its seats for the new hold (Inventory ignores a
      # lapsed hold); a SoldOut below rolls this back too.
      held&.update!(status: "expired", expires_at: Time.current)
      Ticketing::Inventory.reserve!(listing, requests) do
        order = TicketOrder.create!(organization: listing.organization, ticket_listing: listing, status: "pending",
                                    channel: channel, money_path: "cocoscout", fee_mode: listing.effective_fee_mode,
                                    expires_at: TicketOrder::HOLD.from_now, ticket_discount_code: discount,
                                    client_ip: client_ip, referrer: referrer.to_s.first(500).presence)
        requests.each { |tier, count| count.times { add_ticket(order, tier, discount) } }
        price!(order)
      end
    end
    order
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, there aren't enough seats left for that. Try fewer tickets."
  end

  # A live hold's tickets by type: { tier_id => count }.
  def self.held_quantities(order)
    order.tickets.group(:ticket_tier_id).count
  end

  def self.same_request?(order, requests, discount)
    held_quantities(order) == requests.to_h { |tier, count| [ tier.id, count ] } &&
      order.ticket_discount_code_id == discount&.id
  end

  # The order's numbers, from its tickets and their tax.
  def self.price!(order)
    tickets = order.tickets.includes(:tax_lines).to_a
    items = tickets.map do |ticket|
      { price_cents: ticket.price_cents, discount_cents: ticket.discount_cents,
        tax_cents: ticket.tax_lines.reject(&:included).sum(&:tax_cents) }
    end
    quote = TicketPricing.quote(items: items, fee_mode: order.fee_mode, money_path: order.money_path)
    order.update!(subtotal_cents: quote.subtotal_cents, discount_cents: quote.discount_cents,
                  tax_cents: tickets.sum(&:tax_cents), platform_fee_cents: quote.platform_fee_cents,
                  processing_cents: quote.processing_cents, buyer_fee_cents: quote.buyer_fee_cents,
                  total_cents: quote.total_cents, org_net_cents: quote.org_net_cents)
    order
  end

  # A code works when it's active, inside its dates and uses, and covers this
  # show (directly, through its production, or org-wide).
  def self.find_discount(listing, code)
    TicketDiscountCode.where(organization_id: listing.organization_id, code: code, active: true)
                      .detect { |discount| discount.applies_to?(listing) && discount.usable? }
  end

  def self.requested_tiers(listing, quantities, code, at_door: false)
    tiers = listing.ticket_tiers.active.select { |tier| at_door || tier.selling? }.index_by(&:id)
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

  # One held ticket, its discount, and its tax — recorded now so the price the
  # buyer is quoted is the price they pay, even if the theater changes its tax
  # rate while they're checking out.
  def self.add_ticket(order, tier, discount)
    listing = order.ticket_listing
    off = discount&.applies_to?(listing, tier) ? discount.discount_cents_for(tier.price_cents) : 0
    ticket = order.tickets.create!(ticket_tier: tier, ticket_listing: listing, status: "reserved",
                                   price_cents: tier.price_cents, discount_cents: off)
    tax = TaxCalculator.for_ticket(listing, tier, tier.price_cents - off)
    tax.lines.each do |line|
      TaxLine.create!(organization_id: order.organization_id, taxable: ticket, tax_rate: line.tax_rate,
                      name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                      included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                      base_cents: line.base_cents, tax_cents: line.tax_cents,
                      sale_date: Date.current, event_date: listing.starts_at&.to_date)
    end
    ticket.update_columns(tax_cents: tax.tax_cents)
  end

  private_class_method :requested_tiers, :add_ticket, :same_request?
end

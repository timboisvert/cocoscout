# frozen_string_literal: true

module Ticketing
  # Every number about one show's tickets, worked out in one place so the
  # dashboard, the show page, the producer view, reports and the emails can
  # never disagree. Seats come from Ticketing::Inventory (still the only seat
  # counter); everything else from the show's orders, tickets and refunds.
  #
  #   sold        — tickets people hold (paid, comped, or at the door), refunds out
  #   comps       — the free ones among them, given by the theater
  #   gross_cents — what the tickets sold for: price after discounts, without
  #                 tax or fees (the same face value Show Financials records)
  #   net_cents   — what the theater keeps: after our fee, card processing and
  #                 refunds, and without the tax it collected (that's the
  #                 government's); cash at the door counts in full. Money
  #                 for tickets moved to another date counts there.
  #
  # Build many at once with .for(listings): a handful of queries in all.
  class ListingStats
    # One ticket type on this date. sold is every ticket held here, comps
    # included; sold_anywhere and seats_to_sell read it the way the Sold tile
    # does: sold here or elsewhere, of the seats left once comps are set aside.
    # A plain type's sold and money take in its tickets sold in bundles
    # (in_bundles, bundle_cents), since they use its seats; a bundle's row
    # counts purchases of it, and its tickets are the type's.
    TierRow = Data.define(:tier, :sold, :seats, :held, :remaining, :gross_cents, :outside, :comps, :in_bundles, :bundle_cents) do
      def sold_here = sold - comps
      def sold_anywhere = sold_here + outside
      def seats_to_sell = seats && [ seats - comps, 0 ].max
    end
    ProductRow = Data.define(:name, :sold, :gross_cents, :handed_over)
    CHANNELS = { "online" => "Online", "embed" => "Your website", "door_cash" => "Cash at the door",
                 "door_card" => "Card at the door", "comp" => "Comps", "pass" => "Pass credits", "door_pass" => "Pass credits at the door" }.freeze

    attr_reader :listing

    def self.for(listings)
      listings = Array(listings)
      return {} if listings.empty?

      ids = listings.map(&:id)
      tickets = Ticket.joins(:ticket_order).where(ticket_listing_id: ids)
                      .where(ticket_orders: { status: TicketOrder::WAS_PAID })
                      .select("tickets.*, ticket_orders.channel AS order_channel, ticket_orders.paid_at AS order_paid_at, " \
                              "ticket_orders.ticket_discount_code_id AS order_code_id")
                      .to_a.group_by(&:ticket_listing_id)
      orders = TicketOrder.where(ticket_listing_id: ids, status: TicketOrder::WAS_PAID).to_a.group_by(&:ticket_listing_id)
      moved_out = TicketExchange.joins(:from_order).where(ticket_orders: { ticket_listing_id: ids })
                                .group("ticket_orders.ticket_listing_id").sum(:moved_cents)
      refunds = TicketRefund.succeeded.joins(:ticket_order).where(ticket_orders: { ticket_listing_id: ids })
                            .select("ticket_refunds.*, ticket_orders.ticket_listing_id AS listing_id")
                            .to_a.group_by(&:listing_id)
      included_tax = TaxLine.joins("JOIN tickets ON tickets.id = tax_lines.taxable_id")
                            .where(taxable_type: "Ticket", tickets: { ticket_listing_id: ids })
                            .group("tax_lines.taxable_id", "tax_lines.included").sum(:tax_cents)
      tiers = TicketTier.where(ticket_listing_id: ids).order(:position, :id).to_a.group_by(&:ticket_listing_id)
      items = TicketOrderItem.joins(:ticket_order).where(ticket_listing_id: ids, status: TicketOrderItem::SOLD_STATUSES)
                             .where(ticket_orders: { status: TicketOrder::WAS_PAID }).to_a.group_by(&:ticket_listing_id)
      item_tax = TaxLine.joins("JOIN ticket_order_items ON ticket_order_items.id = tax_lines.taxable_id")
                        .where(taxable_type: "TicketOrderItem", included: true, ticket_order_items: { ticket_listing_id: ids })
                        .group("tax_lines.taxable_id").sum(:tax_cents)

      listings.to_h do |listing|
        [ listing.id, new(listing, tickets: tickets.fetch(listing.id, []), orders: orders.fetch(listing.id, []),
                                   refunds: refunds.fetch(listing.id, []), tax: included_tax, tiers: tiers.fetch(listing.id, []),
                                   moved_out_cents: moved_out.fetch(listing.id, 0), items: items.fetch(listing.id, []), item_tax: item_tax) ]
      end
    end

    # One show's numbers (for many at once, use .for).
    def self.of(listing)
      self.for([ listing ]).fetch(listing.id)
    end

    def initialize(listing, tickets:, orders:, refunds:, tax:, tiers:, moved_out_cents: 0, items: [], item_tax: {})
      @listing = listing
      @moved_out_cents = moved_out_cents
      @items = items
      @item_tax = item_tax
      @tickets = tickets
      @orders = orders
      @refunds = refunds
      @tax = tax
      @tiers = tiers
    end

    def inventory
      @inventory ||= listing.inventory
    end

    def capacity
      inventory.capacity
    end

    def remaining
      inventory.remaining
    end

    # Tickets sold on other sites, as typed on the show's page, and where.
    def outside_sold
      inventory.outside_sold
    end

    def outside_words(tier: nil)
      inventory.outside_words(tier: tier)
    end

    def outside_lines(tier: nil)
      inventory.outside_lines(tier: tier)
    end

    def outside_amounts(tier: nil)
      inventory.outside_amounts(tier: tier)
    end

    def outside_by_site(tier: nil)
      inventory.outside_by_site(tier: tier)
    end

    def outside_cents(tier: nil)
      inventory.outside_cents(tier: tier)
    end

    def held_tickets
      @tickets.select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    end

    def sold
      held_tickets.size
    end

    def comps
      held_tickets.count { |t| t.order_channel == "comp" }
    end

    def paid_sold
      sold - comps
    end

    # A date the way a manager reads it at a glance (Tim, 2026-10-09):
    # every ticket sold, here or on another site, of the seats there are to
    # sell once comps are set aside: "7 of 37 sold · 3 comps". Where a
    # ticket sold matters less here than how many seats are left.
    def sold_anywhere
      paid_sold + outside_sold
    end

    def seats_to_sell
      capacity && [ capacity - comps, 0 ].max
    end

    def checked_in
      held_tickets.count(&:checked_in?)
    end

    # Once the show has started: who held a ticket and didn't come.
    def no_shows
      listing.show.date_and_time <= Time.current ? sold - checked_in : nil
    end

    def gross_cents
      held_tickets.sum { |t| face_cents(t) }
    end

    def tax_cents
      held_tickets.sum { |t| @tax.fetch([ t.id, true ], 0) + @tax.fetch([ t.id, false ], 0) }
    end

    def net_cents
      kept = @orders.sum do |order|
        case order.money_path
        when "cocoscout" then order.org_net_cents
        when "cash" then order.total_cents
        else 0
        end
      end
      kept - @refunds.sum(&:org_debit_cents) - @moved_out_cents - tax_cents
    end

    def refunded_tickets
      @tickets.count { |t| t.status == "refunded" }
    end

    def refunded_cents
      @refunds.sum(&:amount_cents)
    end

    def sold_since(time)
      held_tickets.count { |t| t.order_paid_at && t.order_paid_at >= time }
    end

    def by_tier
      @tiers.map do |tier|
        if tier.bundle?
          # Purchases of the bundle (its tickets are its type's, counted there too).
          mine = held_tickets.select { |t| t.bundle_tier_id == tier.id }
          admits = [ tier.admits.to_i, 1 ].max
          TierRow.new(tier: tier, sold: mine.size / admits, seats: nil, held: inventory.held(tier: tier) / admits,
                      remaining: tier.units_for(inventory.remaining(tier: tier)), gross_cents: mine.sum { |t| face_cents(t) }, outside: 0,
                      comps: mine.count { |t| t.order_channel == "comp" } / admits, in_bundles: 0, bundle_cents: 0)
        else
          mine = held_tickets.select { |t| t.ticket_tier_id == tier.id }
          TierRow.new(tier: tier, sold: mine.size, seats: tier.quantity, held: inventory.held(tier: tier),
                      remaining: inventory.remaining(tier: tier), gross_cents: mine.sum { |t| face_cents(t) }, outside: inventory.outside(tier: tier),
                      comps: mine.count { |t| t.order_channel == "comp" },
                      in_bundles: mine.count { |t| t.bundle_tier_id.present? }, bundle_cents: mine.select { |t| t.bundle_tier_id.present? }.sum { |t| face_cents(t) })
        end
      end
    end


    # Products (bottles) bought with the tickets, still held: how many, and
    # what they sold for without tax.
    def products_sold
      @items.sum(&:quantity)
    end

    def product_cents
      @items.sum { |i| i.price_cents - @item_tax.fetch(i.id, 0) }
    end

    def by_product
      @items.group_by(&:name).map do |name, rows|
        ProductRow.new(name: name, sold: rows.sum(&:quantity), gross_cents: rows.sum { |i| i.price_cents - @item_tax.fetch(i.id, 0) },
                       handed_over: rows.sum(&:fulfilled_quantity))
      end
    end

    # Each discount code used: [code, orders, cents off].
    def discount_uses
      used = @orders.select { |o| o.ticket_discount_code_id && o.exchanged_from_id.nil? }.group_by(&:ticket_discount_code_id)
      return [] if used.empty?

      codes = TicketDiscountCode.where(id: used.keys).index_by(&:id)
      used.map { |id, orders| [ codes[id]&.code, orders.size, orders.sum(&:discount_cents) ] }
    end


    private

    def face_cents(ticket)
      ticket.price_cents - ticket.discount_cents - @tax.fetch([ ticket.id, true ], 0)
    end
  end
end

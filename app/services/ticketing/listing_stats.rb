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
    TierRow = Data.define(:tier, :sold, :seats, :held, :remaining, :gross_cents)
    CHANNELS = { "online" => "Online", "embed" => "Your website", "door_cash" => "Cash at the door",
                 "door_card" => "Card at the door", "comp" => "Comps" }.freeze

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

      listings.to_h do |listing|
        [ listing.id, new(listing, tickets: tickets.fetch(listing.id, []), orders: orders.fetch(listing.id, []),
                                   refunds: refunds.fetch(listing.id, []), tax: included_tax, tiers: tiers.fetch(listing.id, []),
                                   moved_out_cents: moved_out.fetch(listing.id, 0)) ]
      end
    end

    # One show's numbers (for many at once, use .for).
    def self.of(listing)
      self.for([ listing ]).fetch(listing.id)
    end

    def initialize(listing, tickets:, orders:, refunds:, tax:, tiers:, moved_out_cents: 0)
      @listing = listing
      @moved_out_cents = moved_out_cents
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
        mine = held_tickets.select { |t| t.ticket_tier_id == tier.id }
        TierRow.new(tier: tier, sold: mine.size, seats: tier.quantity, held: inventory.held(tier: tier),
                    remaining: inventory.remaining(tier: tier), gross_cents: mine.sum { |t| face_cents(t) })
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

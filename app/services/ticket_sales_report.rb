# frozen_string_literal: true

# A theater's ticket sales for a month or a quarter (Ticketing → Reports):
# the totals, then the same money by show, by ticket type, by channel and
# by day, plus a buyer list. Counted by the day each order was paid, or by
# the day of its show (basis "sale" / "event"), like the taxes report.
#
# The numbers mean what they mean everywhere else in Ticketing:
#   tickets     — paid tickets held at the end (refunded ones drop out);
#                 comps are counted apart
#   gross_cents — face value after discounts, without tax or fees (what
#                 Show Financials records)
#   net_cents   — what the theater keeps after our fee, card processing,
#                 refunds and the tax it collected
class TicketSalesReport
  BASES = %w[sale event].freeze

  Summary = Data.define(:tickets, :comps, :orders, :gross_cents, :product_cents, :tax_cents, :platform_fee_cents,
                        :processing_cents, :buyer_fee_cents, :refunded_cents, :net_cents)
  ShowRow = Data.define(:listing, :tickets, :comps, :gross_cents, :product_cents, :refunded_cents, :net_cents, :money_state)
  TypeRow = Data.define(:name, :tickets, :gross_cents)
  ChannelRow = Data.define(:channel, :label, :orders, :tickets, :gross_cents)

  attr_reader :from, :to, :basis

  def initialize(organization, from:, to:, basis: "sale")
    @organization = organization
    @from = from
    @to = to
    @basis = BASES.include?(basis) ? basis : "sale"
  end

  def summary
    @summary ||= Summary.new(
      tickets: paid_tickets.size, comps: comp_tickets.size, orders: orders.count { |o| o.channel != "comp" },
      gross_cents: paid_tickets.sum { |t| face(t) }, product_cents: items.sum { |i| product_face(i) }, tax_cents: tax_cents(orders),
      platform_fee_cents: orders.sum(&:platform_fee_cents) - refunds.sum(&:platform_fee_waived_cents),
      processing_cents: orders.sum(&:processing_cents), buyer_fee_cents: orders.sum(&:buyer_fee_cents),
      refunded_cents: refunds.sum(&:amount_cents), net_cents: net_cents(orders, refunds)
    )
  end

  # Each show with sales in the period, soonest first.
  def by_show
    @by_show ||= orders.group_by(&:ticket_listing).map do |listing, rows|
      ids = rows.map(&:id).to_set
      tickets = paid_tickets.select { |t| ids.include?(t.ticket_order_id) }
      show_refunds = refunds.select { |r| ids.include?(r.ticket_order_id) }
      ShowRow.new(listing: listing, tickets: tickets.size, comps: comp_tickets.count { |t| ids.include?(t.ticket_order_id) },
                  gross_cents: tickets.sum { |t| face(t) }, product_cents: items.select { |i| ids.include?(i.ticket_order_id) }.sum { |i| product_face(i) },
                  refunded_cents: show_refunds.sum(&:amount_cents), net_cents: net_cents(rows, show_refunds),
                  money_state: money_state(listing))
    end.sort_by { |row| row.listing.show.date_and_time }
  end

  # Ticket types by name across the period's shows.
  def by_type
    @by_type ||= paid_tickets.group_by { |t| t.ticket_tier.name }.map do |name, tickets|
      TypeRow.new(name: name, tickets: tickets.size, gross_cents: tickets.sum { |t| face(t) })
    end.sort_by { |row| [ -row.gross_cents, row.name ] }
  end

  # Where the orders came from.
  def by_channel
    @by_channel ||= orders.group_by(&:channel).map do |channel, rows|
      ids = rows.map(&:id).to_set
      tickets = held_tickets.select { |t| ids.include?(t.ticket_order_id) }
      ChannelRow.new(channel: channel, label: Ticketing::ListingStats::CHANNELS.fetch(channel, channel), orders: rows.size,
                     tickets: tickets.size, gross_cents: tickets.sum { |t| face(t) })
    end.sort_by { |row| -row.tickets }
  end

  # Paid tickets per day of the period, for the chart: by the day they sold,
  # or the day of their show.
  def by_day
    counts = Hash.new(0)
    per_order = paid_tickets.group_by(&:ticket_order_id).transform_values(&:size)
    orders.each do |order|
      day = basis == "event" ? order.ticket_listing.show.date_and_time.to_date : order.paid_at&.in_time_zone&.to_date
      counts[day] += per_order.fetch(order.id, 0) if day
    end
    (from..to).to_h { |day| [ day.iso8601, counts[day] ] }
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << [ "Show", "Date", "Tickets", "Comps", "Ticket sales", "Products", "Refunded", "You keep", "Money" ]
      by_show.each do |row|
        csv << [ row.listing.display_title, row.listing.show.date_and_time.strftime("%Y-%m-%d %H:%M"), row.tickets, row.comps,
                 dollars(row.gross_cents), dollars(row.product_cents), dollars(row.refunded_cents), dollars(row.net_cents), row.money_state ]
      end
      csv << [ "Total", nil, summary.tickets, summary.comps, dollars(summary.gross_cents), dollars(summary.product_cents),
               dollars(summary.refunded_cents), dollars(summary.net_cents), nil ]
    end
  end

  # Everyone who bought in the period, one row per order.
  def buyers_csv
    require "csv"
    CSV.generate do |csv|
      csv << [ "Name", "Email", "Phone", "Show", "Show date", "Order", "Bought", "Tickets", "Products", "Total", "How", "Status" ]
      orders.sort_by { |o| o.paid_at || Time.at(0) }.each do |order|
        held = held_tickets.select { |t| t.ticket_order_id == order.id }
        csv << [ order.buyer_name, order.buyer_email, order.buyer_phone, order.ticket_listing.display_title,
                 order.ticket_listing.show.date_and_time.strftime("%Y-%m-%d %H:%M"), order.code, order.paid_at&.strftime("%Y-%m-%d %H:%M"),
                 held.size, items.select { |i| i.ticket_order_id == order.id }.map(&:label).join("; "), dollars(order.total_cents),
                 Ticketing::ListingStats::CHANNELS.fetch(order.channel, order.channel), order.status.humanize ]
      end
    end
  end

  private

  # The period's orders: paid (whatever happened since), by sale day or show day.
  def orders
    @orders ||= begin
      scope = @organization.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(ticket_listing: { show: :location })
      if basis == "event"
        scope.joins(ticket_listing: :show).where(shows: { date_and_time: from.beginning_of_day..to.end_of_day })
      else
        scope.where(paid_at: from.beginning_of_day..to.end_of_day)
      end.to_a
    end
  end

  def order_ids
    @order_ids ||= orders.map(&:id)
  end

  def held_tickets
    @held_tickets ||= Ticket.joins(:ticket_order).where(ticket_order_id: order_ids, status: Ticket::SOLD_STATUSES)
                            .select("tickets.*, ticket_orders.channel AS order_channel").includes(:ticket_tier).to_a
  end

  def paid_tickets
    @paid_tickets ||= held_tickets.reject { |t| t.order_channel == "comp" }
  end

  def comp_tickets
    @comp_tickets ||= held_tickets.select { |t| t.order_channel == "comp" }
  end

  def items
    @items ||= TicketOrderItem.where(ticket_order_id: order_ids, status: TicketOrderItem::SOLD_STATUSES).to_a
  end

  # Refunds given on the period's orders (whenever they were given).
  def refunds
    @refunds ||= TicketRefund.succeeded.where(ticket_order_id: order_ids).to_a
  end

  def included_tax
    @included_tax ||= TaxLine.where(included: true)
                             .where(taxable_type: "Ticket", taxable_id: held_tickets.map(&:id))
                             .or(TaxLine.where(included: true, taxable_type: "TicketOrderItem", taxable_id: items.map(&:id)))
                             .group(:taxable_type, :taxable_id).sum(:tax_cents)
  end

  def face(ticket)
    ticket.price_cents - ticket.discount_cents - included_tax.fetch([ "Ticket", ticket.id ], 0)
  end

  def product_face(item)
    item.price_cents - included_tax.fetch([ "TicketOrderItem", item.id ], 0)
  end

  def tax_cents(rows)
    rows.sum(&:tax_cents) - refunds.select { |r| rows.any? { |o| o.id == r.ticket_order_id } }.sum(&:tax_cents)
  end

  # What the theater keeps of these orders: as the dashboard counts it.
  def net_cents(rows, row_refunds)
    kept = rows.sum do |order|
      case order.money_path
      when "cocoscout" then order.org_net_cents
      when "cash" then order.total_cents
      else 0
      end
    end
    moved = TicketExchange.where(from_order_id: rows.map(&:id))
    kept - rows.sum(&:tax_cents) - row_refunds.sum(&:org_debit_cents) + row_refunds.sum(&:tax_cents) -
      moved.sum(:moved_cents) + moved.sum(:tax_cents)
  end

  def money_state(listing)
    if listing.status == "canceled" || listing.show.canceled then "Refunding buyers"
    elsif listing.released_at then "In your balance"
    else "Held for the show"
    end
  end

  def dollars(cents)
    format("%.2f", cents / 100.0)
  end
end

# frozen_string_literal: true

# The variables each Ticketing notice fills its template with, worked out from
# the records it's about. Numbers come from Ticketing::ListingStats, so an
# email never disagrees with the show's page. Anything a buyer typed is
# escaped before it lands in an email.
class TicketingNotificationContent
  def self.routes
    Rails.application.routes.url_helpers
  end

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  def self.money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
  end

  def self.h(text)
    ERB::Util.html_escape(text.to_s)
  end

  def self.show_vars(listing)
    show = listing.show
    {
      show_title: h(listing.display_title),
      show_date: show.date_and_time.strftime("%A, %B %-d"),
      show_time: show.date_and_time.strftime("%-l:%M %p"),
      show_url: routes.manage_ticket_listing_url(listing, **url_options)
    }
  end

  def self.sold_line(stats)
    stats.capacity ? "#{stats.sold} of #{stats.capacity} sold" : "#{stats.sold} sold"
  end

  # "3 Champagne bottles and 2 Programs", or "" when none.
  def self.products_line(stats)
    stats.by_product.map { |row| "#{row.sold} #{h(row.name)}" }.to_sentence
  end

  # A small table for an email: header cells, then rows of cells. All inline
  # styles, no newlines (ContentTemplate turns newlines into <br>).
  def self.table(head, rows, right_from: 1)
    cell = lambda do |text, index, header: false, strong: false|
      align = index >= right_from ? "right" : "left"
      style = "padding:6px 10px;border-bottom:1px solid #e5e7eb;text-align:#{align};font-size:14px;#{'white-space:nowrap;' if index >= right_from}" \
              "#{'color:#6b7280;font-size:12px;text-transform:uppercase;letter-spacing:0.03em;' if header}#{'font-weight:600;' if strong}"
      %(<#{header ? 'th' : 'td'} style="#{style}">#{text}</#{header ? 'th' : 'td'}>)
    end
    body = rows.map do |row|
      strong = row.is_a?(Hash)
      cells = strong ? row[:cells] : row
      "<tr>#{cells.each_with_index.map { |text, i| cell.call(text, i, strong: strong) }.join}</tr>"
    end.join
    %(<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;margin:8px 0"><tr>#{head.each_with_index.map { |text, i| cell.call(text, i, header: true) }.join}</tr>#{body}</table>)
  end

  # Sales by ticket type, then products, then the money: what the show-day
  # and show-summary notices show the theater.
  def self.sales_table(stats, checked_in: false)
    head = [ "Ticket", "Sold", "Sales" ]
    head.insert(2, "In") if checked_in
    rows = stats.by_tier.reject { |r| r.tier.archived_at && r.sold.zero? }.map do |row|
      cells = [ h(row.tier.name), row.seats ? "#{row.sold} of #{row.seats}" : row.sold.to_s, money(row.gross_cents) ]
      cells.insert(2, stats.held_tickets.count { |t| t.ticket_tier_id == row.tier.id && t.checked_in? }.to_s) if checked_in
      cells
    end
    rows << [ "Comps", stats.comps.to_s, *(checked_in ? [ stats.held_tickets.count { |t| t.order_channel == "comp" && t.checked_in? }.to_s ] : []), "—" ] if stats.comps.positive?
    stats.by_product.each do |row|
      cells = [ "#{h(row.name)} (product)", row.sold.to_s, money(row.gross_cents) ]
      cells.insert(2, "#{row.handed_over} delivered") if checked_in
      rows << cells
    end
    total = [ "Total", (stats.sold + stats.products_sold).to_s, money(stats.gross_cents + stats.product_cents) ]
    total.insert(2, stats.checked_in.to_s) if checked_in
    rows << { cells: total }
    table(head, rows)
  end

  def self.sale(order)
    listing = order.ticket_listing
    stats = Ticketing::ListingStats.of(listing)
    held = order.tickets.select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    items = order.ticket_order_items.select(&:sold?)
    show_vars(listing).merge(
      buyer_name: h(order.buyer_name.presence || "Someone"),
      ticket_count: ActionController::Base.helpers.pluralize(held.size, "ticket"),
      ticket_summary: h(held.group_by(&:ticket_tier).map { |tier, ts| "#{ts.size} #{tier.name}" }.join(", ")),
      products: items.map { |i| "#{i.quantity} #{h(i.name)}" }.to_sentence,
      order_total: money(order.total_cents),
      org_net: money(order.org_net_cents - order.tax_cents),
      sold_line: sold_line(stats),
      products_sold: products_line(stats),
      order_url: routes.manage_ticket_order_url(order.id, **url_options)
    )
  end

  def self.show_day(listing)
    stats = Ticketing::ListingStats.of(listing)
    show_vars(listing).merge(sold_line: sold_line(stats), comps: stats.comps.positive? ? stats.comps : "",
                             products_sold: products_line(stats), sales_table: sales_table(stats),
                             door_list_url: routes.manage_ticket_listing_door_list_url(listing, **url_options))
  end

  def self.after_show(listing)
    stats = Ticketing::ListingStats.of(listing)
    show_vars(listing).merge(sold: stats.sold, checked_in: stats.checked_in, no_shows: stats.no_shows.to_i.positive? ? stats.no_shows : "",
                             comps: stats.comps.positive? ? stats.comps : "", sales_table: sales_table(stats, checked_in: true),
                             org_net: money(stats.net_cents))
  end

  def self.milestone(listing, what: nil)
    stats = Ticketing::ListingStats.of(listing)
    tiers = listing.ticket_tiers.active.map { |t| [ h(t.name), t.price_cents.zero? ? "Free" : money(t.price_cents), t.quantity ? t.quantity.to_s : "No limit" ] }
    show_vars(listing).merge(what: h(what || "Every ticket"), remaining: stats.remaining.to_i, sold_line: sold_line(stats),
                             tiers_table: table([ "Ticket", "Price", "Seats" ], tiers),
                             public_url: routes.short_link_url(code: ShortLink.canonical_for!(listing.production).code, date: ShortLink.date_suffix(listing.show), **url_options))
  end

  def self.refund(refund, problem: nil)
    order = refund.ticket_order
    what = [ (ActionController::Base.helpers.pluralize(refund.ticket_ids.size, "ticket") if refund.ticket_ids.any?),
             (refund.items.map(&:label).map { |l| h(l) }.to_sentence if refund.item_ids.any?) ].compact.join(" and ")
    money_note = case order.money_path
    when "cash" then "It was a cash sale at the door, so the money is handed back from the cash box."
    when "none" then "These were comps, so no money moves."
    else order.ticket_listing.released_at ? "It comes out of your available balance." : "It comes out of what this show has sold."
    end
    show_vars(order.ticket_listing).merge(
      buyer_name: h(order.buyer_name.presence || "the buyer"),
      amount: money(refund.amount_cents),
      ticket_count: ActionController::Base.helpers.pluralize(refund.ticket_ids.size, "ticket"),
      what: what.presence || "the price difference",
      fees_kept: refund.keep_fees ? "yes" : "",
      refunded_by: h(refund.refunded_by&.person&.name || refund.refunded_by&.email_address || "Someone"),
      reason: h(refund.reason),
      problem: h(problem),
      order_code: order.code,
      money_note: money_note,
      order_url: routes.manage_ticket_order_url(order.id, **url_options)
    )
  end

  def self.dispute(order, opened:, amount_cents:)
    show_vars(order.ticket_listing).merge(
      headline: opened ? "Disputed charge" : "Dispute won",
      explanation: opened ? "The buyer asked their bank for their money back. The amount and Stripe's $15 fee came out of your balance. Respond in Stripe; the check-in times on the order are good evidence." :
                            "The bank sided with you. The money and the dispute fee are back in your balance.",
      buyer_name: h(order.buyer_name.presence || "A buyer"), amount: money(amount_cents), order_code: order.code,
      order_url: routes.manage_ticket_order_url(order.id, **url_options)
    )
  end

  def self.withdrawal(withdrawal)
    sent = withdrawal.status == "sent"
    {
      headline: sent ? "#{money(withdrawal.amount_cents)} is on its way to your bank" : "A withdrawal to your bank didn't go through",
      explanation: if sent
                     "#{withdrawal.automatic ? 'Your automatic withdrawal' : 'Your withdrawal'} of #{money(withdrawal.amount_cents)} left your CocoScout balance. It usually reaches your bank within two business days."
                   else
                     "We couldn't send #{money(withdrawal.amount_cents)}: #{h(withdrawal.error)}. The money is still in your CocoScout balance."
                   end,
      balance_url: routes.manage_ticket_balance_url(**url_options)
    }
  end

  # Money past the 12-month rule, with no bank connected to send it to.
  def self.held_a_year(cents)
    {
      headline: "Connect your bank: #{money(cents)} has been in your balance for over a year",
      explanation: "CocoScout sends money that's been in your balance for more than a year back to your bank. " \
                   "Connect your organization's bank so we can send you #{money(cents)}.",
      balance_url: routes.manage_ticket_balance_url(**url_options)
    }
  end

  def self.cancellation_done(listing, refunded_count:, refunded_cents:, failed_count:)
    show_vars(listing).merge(refunded_count: refunded_count, refunded_amount: money(refunded_cents),
                             failed_count: failed_count.positive? ? failed_count : "",
                             orders_url: routes.manage_ticket_orders_url(listing_id: listing.id, **url_options))
  end

  # Yesterday's sales, by show: what sold, and where each of those shows
  # stands now. Only shows that sold (or were refunded) that day are listed;
  # the digest isn't a status report on every show (Tim, 2026-10-06). A day
  # with no sales and no refunds sends nothing (`anything`).
  def self.daily_summary(organization, day)
    # Moved tickets aren't new sales: count each purchase once, as bought.
    orders = organization.ticket_orders.was_paid.where(exchanged_from_id: nil).where.not(channel: "comp")
                         .where(paid_at: day.all_day).includes(:tickets, ticket_listing: :show)
    refunds = TicketRefund.succeeded.where(organization_id: organization.id, created_at: day.all_day)
                          .includes(ticket_order: { ticket_listing: :show })
    by_show = orders.group_by(&:ticket_listing)
    bought = Ticket::SOLD_STATUSES + %w[exchanged]
    tickets = orders.sum { |o| o.tickets.count { |t| bought.include?(t.status) } }
    sales = orders.sum { |o| o.subtotal_cents - o.discount_cents }
    stats = Ticketing::ListingStats.for(by_show.keys)
    items = TicketOrderItem.where(ticket_order_id: orders.map(&:id), status: TicketOrderItem::SOLD_STATUSES).to_a
    products_sold = items.sum(&:quantity)
    product_sales = items.sum(&:price_cents)
    label = ->(listing) { "#{listing.show.date_and_time.strftime('%a %b %-d')} · #{h(listing.display_title)}" }
    yesterday_rows = by_show.sort_by { |l, _| l.show.date_and_time }.map do |listing, os|
      ids = os.map(&:id).to_set
      count = os.sum { |o| o.tickets.count { |t| bought.include?(t.status) } }
      mine = items.select { |i| ids.include?(i.ticket_order_id) }
      s = stats[listing.id]
      [ label.call(listing), count.to_s, mine.any? ? mine.sum(&:quantity).to_s : "—", money(os.sum { |o| o.subtotal_cents - o.discount_cents }),
        s.capacity ? "#{s.sold} of #{s.capacity}" : s.sold.to_s ]
    end
    yesterday_rows << { cells: [ "Total", tickets.to_s, products_sold.positive? ? products_sold.to_s : "—", money(sales), "" ] } if yesterday_rows.size > 1
    refund_rows = refunds.group_by { |r| r.ticket_order.ticket_listing }.sort_by { |l, _| l.show.date_and_time }.map do |listing, rs|
      [ label.call(listing), rs.sum { |r| r.ticket_ids.size }.to_s, money(rs.sum(&:amount_cents)) ]
    end
    {
      date_label: day.strftime("%A, %B %-d"),
      tickets_sold: tickets, ticket_sales: money(sales),
      products_sold: products_sold.positive? ? ActionController::Base.helpers.pluralize(products_sold, "product") : "",
      product_sales: money(product_sales),
      refunded: refunds.any? ? money(refunds.sum(:amount_cents)) : "",
      yesterday_table: yesterday_rows.any? ? table([ "Show", "Sold", "Products", "Sales", "Now" ], yesterday_rows) : "<p>No sales that day.</p>",
      refunds_table: refund_rows.any? ? %(<h3 style="font-size:15px;margin:24px 0 8px">Refunded</h3>#{table([ 'Show', 'Tickets', 'Refunded' ], refund_rows)}) : "",
      anything: orders.any? || refunds.any?
    }
  end
end

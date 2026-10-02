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

  def self.sale(order)
    listing = order.ticket_listing
    stats = Ticketing::ListingStats.of(listing)
    held = order.tickets.select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    show_vars(listing).merge(
      buyer_name: h(order.buyer_name.presence || "Someone"),
      ticket_count: ActionController::Base.helpers.pluralize(held.size, "ticket"),
      ticket_summary: h(held.group_by(&:ticket_tier).map { |tier, ts| "#{ts.size} #{tier.name}" }.join(", ")),
      order_total: money(order.total_cents),
      org_net: money(order.org_net_cents - order.tax_cents),
      sold_line: sold_line(stats),
      order_url: routes.manage_ticket_order_url(order.id, **url_options)
    )
  end

  def self.show_day(listing)
    stats = Ticketing::ListingStats.of(listing)
    show_vars(listing).merge(sold_line: sold_line(stats), comps: stats.comps.positive? ? stats.comps : "",
                             door_list_url: routes.manage_ticket_listing_door_list_url(listing, **url_options))
  end

  def self.after_show(listing)
    stats = Ticketing::ListingStats.of(listing)
    show_vars(listing).merge(sold: stats.sold, checked_in: stats.checked_in, no_shows: stats.no_shows.to_i.positive? ? stats.no_shows : "",
                             ticket_sales: money(stats.gross_cents), org_net: money(stats.net_cents))
  end

  def self.milestone(listing, what: nil)
    stats = Ticketing::ListingStats.of(listing)
    show_vars(listing).merge(what: h(what || "Every ticket"), remaining: stats.remaining.to_i, sold_line: sold_line(stats),
                             public_url: routes.tickets_event_url(org: TicketingProfile.for(listing.organization).slug, event: listing.slug, **url_options))
  end

  def self.refund(refund, problem: nil)
    order = refund.ticket_order
    show_vars(order.ticket_listing).merge(
      buyer_name: h(order.buyer_name.presence || "the buyer"),
      amount: money(refund.amount_cents),
      ticket_count: ActionController::Base.helpers.pluralize(refund.ticket_ids.size, "ticket"),
      refunded_by: h(refund.refunded_by&.person&.name || refund.refunded_by&.email_address || "Someone"),
      reason: h(refund.reason),
      problem: h(problem),
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

  # Yesterday's sales by show, and how each upcoming show is selling.
  def self.daily_summary(organization, day)
    # Moved tickets aren't new sales: count each purchase once, as bought.
    orders = organization.ticket_orders.was_paid.where(exchanged_from_id: nil).where.not(channel: "comp")
                         .where(paid_at: day.all_day).includes(:tickets, ticket_listing: :show)
    refunds = TicketRefund.succeeded.where(organization_id: organization.id, created_at: day.all_day)
    by_show = orders.group_by(&:ticket_listing)
    bought = Ticket::SOLD_STATUSES + %w[exchanged]
    tickets = orders.sum { |o| o.tickets.count { |t| bought.include?(t.status) } }
    sales = orders.sum { |o| o.subtotal_cents - o.discount_cents }
    upcoming = organization.ticket_listings.joins(:show).where.not(status: %w[draft canceled])
                           .where(shows: { canceled: false, date_and_time: Time.current..14.days.from_now })
                           .order("shows.date_and_time").limit(15).to_a
    stats = Ticketing::ListingStats.for(upcoming)
    row = ->(left, right) { %(<tr><td style="padding:4px 12px 4px 0">#{left}</td><td style="padding:4px 0;text-align:right">#{right}</td></tr>) }
    sales_rows = by_show.map { |listing, os|
      count = os.sum { |o| o.tickets.count { |t| bought.include?(t.status) } }
      row.call("#{listing.show.date_and_time.strftime('%a %b %-d')} · #{h(listing.display_title)}", "+#{count}")
    }
    upcoming_rows = upcoming.map { |listing|
      row.call("#{listing.show.date_and_time.strftime('%a %b %-d')} · #{h(listing.display_title)}", sold_line(stats[listing.id]))
    }
    {
      date_label: day.strftime("%A, %B %-d"),
      tickets_sold: tickets, ticket_sales: money(sales),
      refunded: refunds.any? ? money(refunds.sum(:amount_cents)) : "",
      sales_rows: sales_rows.any? ? "<table>#{sales_rows.join}</table>" : "",
      upcoming_rows: upcoming_rows.any? ? "<table>#{upcoming_rows.join}</table>" : "<p>Nothing on sale in the next two weeks.</p>",
      anything: orders.any? || refunds.any? || upcoming.any?
    }
  end
end

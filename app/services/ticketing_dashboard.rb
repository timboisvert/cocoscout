# frozen_string_literal: true

# Everything Ticketing's home page shows (/manage/ticketing), worked out the
# way the Money hub works out its to-dos: nothing cached, because a nudge
# that's still there after you dealt with it costs trust in all the others.
# Show-level numbers come from Ticketing::ListingStats, so the home page and
# each show's page always agree.
class TicketingDashboard
  UPCOMING_ROWS = 10
  RECENT_ORDERS = 8
  JUST_PLAYED = 5
  # Drafts for shows this close are worth a nudge.
  DRAFT_HORIZON = 14.days
  SOLD_STATUSES = TicketOrder::WAS_PAID

  Summary = Data.define(:tickets, :gross_cents, :net_cents, :refunded_cents)
  Alert = Data.define(:eyebrow, :headline, :body, :actions, :tone)

  attr_reader :period

  def initialize(organization, period: :last_30_days)
    @organization = organization
    @period = FinancialSummaryService::PERIODS.key?(period.to_s.to_sym) ? period.to_s.to_sym : :last_30_days
  end

  def range
    FinancialSummaryService::PERIODS.fetch(@period).call
  end

  # Tickets sold and money in the period: sales by when they were paid,
  # refunds by when they were given.
  def summary
    @summary ||= begin
      orders = paid_orders.where.not(channel: "comp")
      orders = orders.where(paid_at: range) if range
      tickets = Ticket.where(ticket_order_id: orders.select(:id), status: Ticket::SOLD_STATUSES).count
      refunds = TicketRefund.succeeded.where(organization_id: @organization.id)
      refunds = refunds.where(created_at: range) if range
      held = Ticket.where(ticket_order_id: orders.select(:id), status: Ticket::SOLD_STATUSES)
      included_tax = TaxLine.where(taxable_type: "Ticket", taxable_id: held.select(:id), included: true).sum(:tax_cents)
      gross = held.sum("tickets.price_cents - tickets.discount_cents") - included_tax
      moved = TicketExchange.where(from_order_id: orders.select(:id))
      kept = orders.sum("CASE WHEN money_path = 'cocoscout' THEN org_net_cents WHEN money_path = 'cash' THEN total_cents ELSE 0 END") -
             orders.sum(:tax_cents) - refunds.sum(:org_debit_cents) + refunds.sum(:tax_cents) -
             moved.sum(:moved_cents) + moved.sum(:tax_cents)
      Summary.new(tickets: tickets, gross_cents: gross, net_cents: kept, refunded_cents: refunds.sum(:amount_cents))
    end
  end

  # Tickets sold each day of the period (the last 90 days for longer ones).
  def daily_tickets
    from = [ range&.begin, 89.days.ago.beginning_of_day ].compact.max.to_date
    to = [ range&.end&.to_date, Date.current ].compact.min
    return {} if to < from

    orders = paid_orders.where.not(channel: "comp").where(paid_at: from.beginning_of_day..to.end_of_day)
    per_order = Ticket.where(ticket_order_id: orders.select(:id), status: Ticket::SOLD_STATUSES).group(:ticket_order_id).count
    counts = Hash.new(0)
    orders.pluck(:id, :paid_at).each { |id, paid_at| counts[paid_at.in_time_zone.to_date] += per_order.fetch(id, 0) }
    (from..to).to_h { |day| [ day.iso8601, counts[day] ] }
  end

  def coming_up
    @coming_up ||= with_stats(listings.where.not(status: "canceled").where(shows: { canceled: false })
                                      .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
                                      .order("shows.date_and_time").limit(UPCOMING_ROWS))
  end

  def upcoming_count
    listings.where.not(status: "canceled").where("shows.date_and_time >= ?", Time.current.beginning_of_day).count
  end

  def tonight
    coming_up.select { |listing, _| listing.show.date_and_time.to_date == Date.current && listing.status != "draft" }
  end

  def just_played
    @just_played ||= with_stats(listings.where.not(status: %w[canceled draft])
                                        .where("shows.date_and_time < ?", Time.current.beginning_of_day)
                                        .order("shows.date_and_time DESC").limit(JUST_PLAYED))
  end

  def recent_orders
    paid_orders.includes(:tickets, ticket_listing: %i[show production]).order(paid_at: :desc).limit(RECENT_ORDERS)
  end

  def drafts_soon
    listings.where(status: "draft").where(shows: { canceled: false })
            .where(shows: { date_and_time: Time.current..DRAFT_HORIZON.from_now })
  end

  # What needs the theater, most urgent first, at most three.
  def alerts
    routes = Rails.application.routes.url_helpers
    list = []
    profile = TicketingProfile.for(@organization)
    unless profile.enabled?
      list << Alert.new(eyebrow: "Not open yet", headline: "Ticketing is off for #{@organization.name}",
                        body: "Your box office page and checkout stay hidden until it's switched on in Settings.",
                        actions: [ { text: "Open settings", path: routes.manage_ticketing_settings_path } ], tone: :pink)
    end
    tonight.each do |listing, stats|
      list << Alert.new(eyebrow: "Tonight", headline: "#{listing.display_title} at #{listing.show.date_and_time.strftime('%-l:%M %p')}: #{stats.sold}#{" of #{stats.capacity}" if stats.capacity} sold",
                        body: "#{stats.comps.positive? ? "Including #{stats.comps} comps. " : ''}Open the door on a phone to scan tickets and sell at the door.",
                        actions: [ { text: "Open the door", path: routes.door_path(listing) }, { text: "Guest list", path: routes.manage_ticket_listing_path(listing) } ],
                        tone: :pink)
    end
    canceled_with_holders = listings.where(shows: { canceled: true }).where.not(status: "canceled")
                                    .where("shows.date_and_time > ?", Time.current)
                                    .where(id: TicketOrder.paid_like.select(:ticket_listing_id))
    canceled_with_holders.each do |listing|
      list << Alert.new(eyebrow: "Show canceled", headline: "#{listing.display_title} is canceled but people hold tickets",
                        body: "Cancel its ticket sales to refund them and let them know.",
                        actions: [ { text: "Refund buyers", path: routes.manage_ticket_listing_cancel_path(listing) } ], tone: :amber)
    end
    changed = listings.where(id: TicketShowChange.changed_orders.select(:ticket_listing_id)).where.not(status: %w[draft canceled])
                      .where(shows: { canceled: false }).where("shows.date_and_time > ?", Time.current).order("shows.date_and_time")
    changed.each do |listing|
      list << Alert.new(eyebrow: "The show changed", headline: "#{listing.display_title} moved after people bought tickets",
                        body: "It's now #{listing.show.date_and_time.strftime('%A, %B %-d at %-l:%M %p')}. Let its buyers know.",
                        actions: [ { text: "Tell buyers", path: routes.manage_ticket_listing_change_path(listing) } ], tone: :amber)
    end
    failed_refunds = TicketRefund.where(organization_id: @organization.id, status: "failed").where(created_at: 30.days.ago..)
    if failed_refunds.exists?
      list << Alert.new(eyebrow: "Refunds", headline: "#{failed_refunds.count} #{failed_refunds.count == 1 ? 'refund' : 'refunds'} didn't go through",
                        body: "The buyer hasn't been refunded. Open the order to try again.",
                        actions: [ { text: "See orders", path: routes.manage_ticket_orders_path(status: "paid") } ], tone: :amber)
    end
    disputed = OrgCashEntry.where(organization_id: @organization.id, entry_type: "ticket_dispute").where(amount_cents: ...0)
    if disputed.exists?
      list << Alert.new(eyebrow: "Disputes", headline: "#{disputed.count} disputed #{disputed.count == 1 ? 'charge' : 'charges'}",
                        body: "A buyer asked their bank for the money back. Respond in Stripe; check-in times on the order are good evidence.",
                        actions: [ { text: "See orders", path: routes.manage_ticket_orders_path } ], tone: :amber)
    end
    count = drafts_soon.count
    if count.positive?
      list << Alert.new(eyebrow: "Not on sale yet", headline: "#{count} #{count == 1 ? 'show' : 'shows'} in the next two weeks #{count == 1 ? "isn't" : "aren't"} on sale",
                        body: "They're drafts: nobody can buy tickets until you put them on sale.",
                        actions: [ count == 1 ? { text: "Open it", path: routes.manage_ticket_listing_path(drafts_soon.first) } : { text: "See shows", path: routes.manage_ticket_listings_path } ], tone: :amber)
    end
    if BalanceWithdrawal.where(organization_id: @organization.id, status: "failed").where(created_at: 14.days.ago..).exists?
      list << Alert.new(eyebrow: "Withdrawal", headline: "A withdrawal to your bank didn't go through",
                        body: "The money is still in your CocoScout balance.",
                        actions: [ { text: "Your balance", path: routes.manage_ticket_balance_path } ], tone: :amber)
    end
    list.first(3)
  end

  private

  def listings
    @organization.ticket_listings.joins(:show).includes(:production, show: %i[location location_space])
  end

  def paid_orders
    @organization.ticket_orders.where(status: SOLD_STATUSES)
  end

  def with_stats(scope)
    rows = scope.to_a
    stats = Ticketing::ListingStats.for(rows)
    rows.map { |listing| [ listing, stats.fetch(listing.id) ] }
  end
end

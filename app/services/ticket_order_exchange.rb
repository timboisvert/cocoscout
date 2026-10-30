# frozen_string_literal: true

# Moving a buyer's tickets to another date of the same production, or to
# another ticket type on the same date (a Splatter Zone comp that should
# have been General Admission): the manager's "Move tickets" on an order.
# (Buyers can't do it themselves yet.)
#
# The buyer keeps their payment. A new order on the new date holds new
# tickets with new codes, linked back by exchanged_from_id (refunds go back
# through the original payment: TicketOrder#payment_intent_id), and its email
# brings the new tickets. The old tickets stop working (status "exchanged").
# The theater's money moves with them: out of the old show's money, into the
# new show's (the ticket_exchange_out / ticket_exchange_in cash entries, which
# TicketBalance places by show). So do the books: the face value and tax
# leave one show and join the other. Both shows' financials resync.
#
# Same price: nothing changes hands. A cheaper ticket type refunds the
# difference to the card, through the normal refund path. A pricier one is
# refused: refund them and let them buy again. A ticket that cost nothing (a
# comp) stays free, whatever type it becomes.
class TicketOrderExchange
  class Error < StandardError; end

  # One ticket and what it becomes. bundle_tier: the bundle it's in on the new
  # date ("4 × General for $70"), when it came from one.
  Row = Data.define(:ticket, :tier, :price_cents, :discount_cents, :tax_lines, :bundle_tier) do
    def initialize(bundle_tier: nil, **rest) = super(bundle_tier:, **rest)
    def paid_cents = price_cents - discount_cents
    def tax_cents = tax_lines.sum(&:tax_cents)
    def added_tax_cents = tax_lines.reject(&:included).sum(&:tax_cents)
    def face_cents = paid_cents - tax_lines.select(&:included).sum(&:tax_cents)
    def amount_cents = paid_cents + added_tax_cents
  end

  # Everything a move would do, worked out before it happens.
  Plan = Data.define(:order, :target, :rows, :old_face_cents, :old_tax_cents, :new_face_cents, :new_tax_cents,
                     :old_amount_cents, :new_amount_cents, :fees_cents, :platform_fee_cents, :processing_cents, :moved_cents) do
    def difference_cents = old_amount_cents - new_amount_cents
    def tickets = rows.map(&:ticket)
    def same_date? = target.id == order.ticket_listing_id
  end

  # Where these tickets can move: the other dates of the same production, on
  # sale and still to come, and their own date, for another ticket type.
  def self.targets(order)
    listing = order.ticket_listing
    TicketListing.where(organization_id: order.organization_id, production_id: listing.production_id)
                 .where.not(status: "canceled").joins(:show).where(shows: { canceled: false })
                 .where("ticket_listings.id = :own OR (ticket_listings.status = 'on_sale' AND shows.date_and_time > :now)",
                        own: listing.id, now: Time.current)
                 .includes(:ticket_tiers, show: %i[location location_space]).order("shows.date_and_time")
  end

  # Tickets that can move: held and not used yet.
  def self.movable(order)
    order.tickets.where(status: "valid").includes(:ticket_tier, :tax_lines).order(:id)
  end

  # What each ticket type becomes: the type with the same name, unless the
  # manager chose another. On their own date there's no default: changing
  # the type is the point.
  def self.tier_map(tickets, target, chosen = {})
    tiers = target.ticket_tiers.reject(&:archived_at)
    chosen = chosen.to_h.transform_keys(&:to_i)
    same_date = tickets.first && tickets.first.ticket_listing_id == target.id
    tickets.map(&:ticket_tier).uniq.to_h do |tier|
      pick = chosen[tier.id].presence&.to_i
      [ tier.id, pick || (tiers.find { |t| t.name.casecmp?(tier.name) }&.id unless same_date) ]
    end
  end

  # Seats left for each ticket type on the target, counting back the seats
  # these tickets give up when they're on the same date. nil = no limit.
  def self.seats_left(target, tickets, inventory = inventory_for(target, tickets))
    target.ticket_tiers.reject(&:archived_at).to_h { |tier| [ tier.id, inventory.remaining(tier: tier) ] }
  end

  def self.inventory_for(target, tickets)
    Ticketing::Inventory.new(target, excluding: (tickets.map(&:id) if tickets.first&.ticket_listing_id == target.id))
  end

  # outside_policy: the manager's Move anyway, for a show that has happened.
  # Moving to another date isn't held to the refund window; that's the usual
  # allowance a theater makes.
  def self.plan(order, target:, ticket_ids: nil, chosen_tiers: {}, outside_policy: false)
    raise Error, "Only a paid order's tickets can move." unless order.paid? && order.money_path.in?(%w[cocoscout none])
    raise Error, "Tickets paid with a gift certificate can't be moved yet. Refund them instead and let them buy again." if order.gift_certificate_cents.positive?
    if order.ticket_listing.show.date_and_time <= Time.current && !outside_policy
      raise Error, "The show has happened, so moving its tickets is outside the refund policy. Turn on Move anyway to move them."
    end
    raise Error, "Choose another date to move them to." unless target && targets(order).exists?(id: target.id)

    tickets = movable(order).to_a
    tickets = tickets.select { |t| ticket_ids.map(&:to_i).include?(t.id) } if ticket_ids.present?
    raise Error, "Choose the tickets to move." if tickets.empty?

    map = tier_map(tickets, target, chosen_tiers)
    tiers = target.ticket_tiers.reject(&:archived_at).index_by(&:id)
    rows = tickets.map { |ticket| row_for(ticket, tiers[map[ticket.ticket_tier_id]], target) }
    if target.id == order.ticket_listing_id && (same = rows.find { |row| (row.bundle_tier || row.tier) == (row.ticket.bundle_tier || row.ticket.ticket_tier) })
      raise Error, "#{same.ticket.ticket_tier.name} tickets are already #{same.tier.name}. Choose another ticket type, or untick them."
    end
    check_seats!(target, rows)
    old_rows = tickets.map { |t| Row.new(ticket: t, tier: t.ticket_tier, price_cents: t.price_cents, discount_cents: t.discount_cents, tax_lines: original_tax(t)) }

    old_amount = old_rows.sum(&:amount_cents)
    new_amount = rows.sum(&:amount_cents)
    raise Error, "With tax, the new tickets cost more than these did. Refund them instead and let them buy again." if new_amount > old_amount

    paid_moving = tickets.count { |t| t.price_cents > t.discount_cents }
    Plan.new(order: order, target: target, rows: rows,
             old_face_cents: old_rows.sum(&:face_cents), old_tax_cents: old_rows.sum(&:tax_cents),
             new_face_cents: rows.sum(&:face_cents), new_tax_cents: rows.sum(&:tax_cents),
             old_amount_cents: old_amount, new_amount_cents: new_amount,
             fees_cents: TicketOrderRefund.fee_share(order, paid_moving),
             platform_fee_cents: order.platform_fee_cents.positive? ? TicketPricing::PLATFORM_FEE_CENTS * paid_moving : 0,
             processing_cents: share(order.processing_cents, paid_moving, TicketOrderRefund.paid_ticket_count(order)),
             moved_cents: moved_cents(order, old_rows, paid_moving))
  end

  # The theater's share of the order that goes with these tickets: exactly
  # their price and tax when the buyer paid the fees; in proportion to it when
  # the theater absorbed them.
  def self.moved_cents(order, old_rows, paid_moving)
    return 0 unless order.money_path == "cocoscout"

    all = order.tickets.includes(:tax_lines).map do |t|
      Row.new(ticket: t, tier: nil, price_cents: t.price_cents, discount_cents: t.discount_cents, tax_lines: original_tax(t))
    end
    whole = all.sum(&:amount_cents)
    return order.org_net_cents if paid_moving == TicketOrderRefund.paid_ticket_count(order) && order.refunded_cents.zero? && order.exchanges_out.none?
    return 0 if whole.zero?

    (order.org_net_cents * old_rows.sum(&:amount_cents)) / whole
  end

  def self.exchange!(order, target:, ticket_ids: nil, chosen_tiers: {}, by: nil, email_them: true, outside_policy: false)
    organization = order.organization
    listing = order.ticket_listing
    exchange = nil
    plan = nil
    OrgCashEntry.with_org_lock(organization) do
      order.with_lock do
        plan = plan(order, target: target, ticket_ids: ticket_ids, chosen_tiers: chosen_tiers, outside_policy: outside_policy)
        if listing.released_at.present? && !plan.same_date? &&
           plan.moved_cents > CocoScoutBalance.available_cents(organization) + SalesTaxSetAside.relief_cents(organization, ticket_ids: plan.tickets.map(&:id))
          raise Error, "This show's money was already spent or withdrawn, so its tickets can't move to a show still to come."
        end

        requests = plan.rows.group_by(&:tier).transform_values(&:size)
        Ticketing::Inventory.reserve!(target, requests, (plan.tickets.map(&:id) if plan.same_date?)) do
          new_order = create_order!(order, plan)
          exchange = TicketExchange.create!(organization: organization, from_order: order, to_order: new_order, exchanged_by: by,
                                            ticket_ids: plan.tickets.map(&:id), moved_cents: plan.moved_cents,
                                            face_cents: plan.old_face_cents, tax_cents: plan.old_tax_cents,
                                            fees_cents: plan.fees_cents, difference_cents: plan.difference_cents)
          retire_old_tickets!(order, plan)
          moved_products = move_products!(order, new_order, plan)
          post_money!(exchange, order, new_order, plan, moved_products)
        end
      end
    end

    if plan.difference_cents.positive? && order.money_path == "cocoscout"
      refund_difference!(exchange, plan, by)
    end
    TicketSalesSync.sync!(listing.show)
    TicketSalesSync.sync!(target.show)
    TicketingMilestones.check!(target)
    TicketOrderMailer.moved(exchange).deliver_later if email_them && order.buyer_email.present?
    exchange
  rescue Ticketing::Inventory::SoldOut
    raise Error, "#{target.display_title} on #{target.show.date_and_time.strftime('%a %b %-d')} doesn't have that many seats left."
  end

  # Each new type has room for the tickets moving into it (its own seats
  # and the show's, reservations in checkout counted), before the review
  # offers the move. exchange! checks again under the lock.
  def self.check_seats!(target, rows)
    inventory = inventory_for(target, rows.map(&:ticket))
    left = seats_left(target, rows.map(&:ticket), inventory)
    rows.group_by(&:tier).each do |tier, moving|
      seats = left[tier.id]
      next if seats.nil? || moving.size <= seats

      raise Error, seats.zero? ? "#{tier.name} has no seats left on #{target.show.date_and_time.strftime('%a %b %-d')}." :
                                 "#{tier.name} has only #{seats} #{seats == 1 ? 'seat' : 'seats'} left on #{target.show.date_and_time.strftime('%a %b %-d')}."
    end
    overall = inventory.remaining
    if overall && rows.size > overall
      raise Error, "#{target.display_title} on #{target.show.date_and_time.strftime('%a %b %-d')} doesn't have that many seats left."
    end
  end

  # The buyer, their payment and their share of the money, on the new date.
  def self.create_order!(order, plan)
    tickets = plan.tickets
    # Free tickets carry the new type's value (a comp of General reads as
    # $20 given, not the Splatter Zone it was); paid ones keep what was paid,
    # with any difference refunded on the new order.
    tickets = plan.rows if plan.old_amount_cents.zero?
    new_order = TicketOrder.create!(
      organization: order.organization, ticket_listing: plan.target, status: "paid", paid_at: order.paid_at,
      channel: order.channel, money_path: order.money_path, fee_mode: order.fee_mode, exchanged_from: order,
      buyer_name: order.buyer_name, buyer_email: order.buyer_email, buyer_phone: order.buyer_phone,
      marketing_opt_in: order.marketing_opt_in, user_id: order.user_id, ticket_discount_code_id: order.ticket_discount_code_id,
      issued_by_id: order.issued_by_id, note: order.note, reminders_opt_out: order.reminders_opt_out,
      subtotal_cents: tickets.sum(&:price_cents), discount_cents: tickets.sum(&:discount_cents),
      tax_cents: plan.old_tax_cents, platform_fee_cents: plan.platform_fee_cents, processing_cents: plan.processing_cents,
      buyer_fee_cents: plan.fees_cents, total_cents: plan.old_amount_cents + plan.fees_cents, org_net_cents: plan.moved_cents
    )
    plan.rows.each do |row|
      ticket = new_order.tickets.create!(ticket_tier: row.tier, bundle_tier: row.bundle_tier, ticket_listing: plan.target, status: "valid",
                                         holder_name: row.ticket.holder_name, price_cents: row.price_cents,
                                         discount_cents: row.discount_cents, tax_cents: row.tax_cents)
      row.tax_lines.each do |line|
        TaxLine.create!(organization_id: order.organization_id, taxable: ticket, tax_rate_id: line.tax_rate_id,
                        name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                        included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                        base_cents: line.base_cents, tax_cents: line.tax_cents,
                        sale_date: Date.current, event_date: plan.target.starts_at&.to_date)
      end
    end
    new_order
  end

  # The old tickets stop working, and their tax leaves the old show's report.
  def self.retire_old_tickets!(order, plan)
    tickets = Ticket.where(id: plan.tickets.map(&:id))
    tickets.update_all(status: "exchanged", updated_at: Time.current)
    TicketOrderRefund.reverse_tax!(order, tickets)
    order.update!(status: "exchanged") unless order.tickets.where(status: Ticket::SOLD_STATUSES).exists?
  end

  # Products bought with the tickets (a bottle for the table) go along when
  # every ticket moves; when only some move, they stay with the first date.
  # Returns their face value (no tax), for the books.
  def self.move_products!(order, new_order, plan)
    return 0 if order.tickets.where(status: Ticket::SOLD_STATUSES).exists?

    items = order.ticket_order_items.sold.includes(:tax_lines).to_a
    return 0 if items.empty?

    items.sum do |item|
      copy = new_order.ticket_order_items.create!(item.attributes.except("id", "ticket_order_id", "ticket_listing_id", "created_at", "updated_at")
                                                    .merge("ticket_listing_id" => plan.target.id))
      item.tax_lines.select { |line| line.reversal_of_id.nil? && line.tax_cents >= 0 }.each do |line|
        TaxLine.create!(line.attributes.except("id", "taxable_id", "created_at", "updated_at")
                            .merge("taxable_id" => copy.id, "sale_date" => Date.current, "event_date" => plan.target.starts_at&.to_date))
      end
      TicketOrderRefund.reverse_tax!(order, TicketOrderItem.where(id: item.id), taxable_type: "TicketOrderItem")
      item.update!(status: "exchanged")
      item.price_cents - item.tax_lines.select { |l| l.included && l.reversal_of_id.nil? }.sum(&:tax_cents)
    end
  end

  # The money and the books follow the tickets from one show to the other.
  def self.post_money!(exchange, order, new_order, plan, moved_products = 0)
    return unless order.money_path == "cocoscout"

    old_listing = order.ticket_listing
    if plan.moved_cents.nonzero?
      OrgCashEntry.post!(organization: order.organization, entry_type: "ticket_exchange_out", amount_cents: -plan.moved_cents,
                         source: exchange, description: "Tickets #{order.code} moved to #{new_order.code}")
      OrgCashEntry.post!(organization: order.organization, entry_type: "ticket_exchange_in", amount_cents: plan.moved_cents,
                         source: exchange, description: "Tickets #{new_order.code} moved from #{order.code}")
    end

    from = { show: old_listing.show, production: old_listing.production }
    to = { show: plan.target.show, production: plan.target.production }
    # On the same date (another ticket type), the sale stays where it was:
    # earned already if the show has happened and its money was released.
    to_account = plan.target.released_at ? :ticket_income : :advance_ticket_sales
    to_product_account = plan.target.released_at ? :product_income : :advance_product_sales
    LedgerPosting.post!(organization: order.organization, source: exchange, kind: "exchange", entry_date: Date.current,
                        memo: "Tickets #{order.code} moved to #{plan.target.display_title}, #{plan.target.show.date_and_time.strftime('%b %-d')}",
                        lines: [
                          { account: old_listing.released_at ? :ticket_income : :advance_ticket_sales, amount_cents: plan.old_face_cents, **from },
                          { account: :tax_to_remit, amount_cents: plan.old_tax_cents, **from },
                          { account: to_account, amount_cents: -plan.old_face_cents, **to },
                          { account: :tax_to_remit, amount_cents: -plan.old_tax_cents, **to },
                          { account: old_listing.released_at ? :product_income : :advance_product_sales, amount_cents: moved_products, **from },
                          { account: to_product_account, amount_cents: -moved_products, **to }
                        ])
  end

  # The new tickets cost less: the difference goes back to the card. If
  # Stripe can't do it, the move stands and the refund shows as failed on the
  # new order, like any other.
  def self.refund_difference!(exchange, plan, by)
    refund = TicketOrderRefund.issue_difference!(exchange.to_order, amount_cents: plan.difference_cents,
                                                                    face_cents: plan.old_face_cents - plan.new_face_cents,
                                                                    tax_cents: plan.old_tax_cents - plan.new_tax_cents, by: by,
                                                                    reason: "Price difference: moved from #{exchange.from_order.code}")
    exchange.update!(ticket_refund: refund)
  rescue TicketOrderRefund::Error => e
    exchange.refund_error = e.message
  end

  # What a ticket becomes on the new date. The same price keeps everything —
  # discount and tax as they were bought. A cheaper type keeps the discount
  # (up to its price) and is taxed as the new date taxes it.
  def self.row_for(ticket, tier, target)
    unless tier
      raise Error, ticket.ticket_listing_id == target.id ? "Choose the ticket type #{ticket.ticket_tier.name} tickets become." :
                                                           "Choose what #{ticket.ticket_tier.name} tickets become on the new date."
    end
    return free_row(ticket, tier) if ticket.price_cents <= ticket.discount_cents
    bundle = bundle_for(ticket, tier)
    return bundle_row(ticket, bundle, target) if bundle
    if tier.bundle?
      raise Error, "#{tier.name} is a bundle. Choose a ticket type for #{ticket.ticket_tier.name} tickets."
    end
    if tier.price_cents > ticket.price_cents
      raise Error, "#{tier.name} costs #{money(tier.price_cents)} on #{target.show.date_and_time.strftime('%a %b %-d')}, " \
                   "more than their #{money(ticket.price_cents)} ticket. Refund them instead and let them buy again."
    end
    return Row.new(ticket: ticket, tier: tier, price_cents: ticket.price_cents, discount_cents: ticket.discount_cents, tax_lines: original_tax(ticket)) if tier.price_cents == ticket.price_cents

    discount = [ ticket.discount_cents, tier.price_cents ].min
    tax = TaxCalculator.for_ticket(target, tier, tier.price_cents - discount)
    Row.new(ticket: ticket, tier: tier, price_cents: tier.price_cents, discount_cents: discount, tax_lines: tax.lines)
  end

  # A ticket that cost nothing (a comp, a free ticket) stays free: the new
  # type at its price, all of it discounted, no tax. Nothing to refund or
  # charge, so any type will do.
  def self.free_row(ticket, tier)
    bundle = bundle_for(ticket, tier)
    raise Error, "#{tier.name} is a bundle. Choose a ticket type for #{ticket.ticket_tier.name} tickets." if tier.bundle? && !bundle

    price = bundle ? TicketTier.split(bundle.price_cents, bundle.admits).max : tier.price_cents
    Row.new(ticket: ticket, tier: tier.base_tier, price_cents: price, discount_cents: price, tax_lines: [], bundle_tier: bundle)
  end

  # A ticket bought in a bundle ("4 × General for $70", each ticket $17.50)
  # moves into the new date's same bundle: the one the manager picked, else
  # the bundle of the same size over the type it maps to (the same name
  # first). Nil when it wasn't from a bundle or the new date has none.
  def self.bundle_for(ticket, tier)
    return nil unless ticket.bundle_tier
    return tier if tier.bundle?

    size = ticket.bundle_tier.admits
    bundles = tier.bundles.reject { |b| b.archived_at || b.admits != size }
    bundles.find { |b| b.name.casecmp?(ticket.bundle_tier.name) } || bundles.first
  end

  # Compared by the bundle's price, never one ticket's (Tim, 2026-10-10: a
  # 4-pack wouldn't move because $20 for one, or $70 for four, beat $17.50).
  # The same bundle price keeps everything; a cheaper one is the new share,
  # with the difference refunded; a pricier one is refused.
  def self.bundle_row(ticket, bundle, target)
    size = bundle.admits
    was = ticket.price_cents * size
    base = bundle.bundle_of
    # A bundle that split unevenly (3 for $50: $16.67, $16.67, $16.66) is
    # still the same price.
    if (bundle.price_cents - was).abs < size
      return Row.new(ticket: ticket, tier: base, price_cents: ticket.price_cents, discount_cents: ticket.discount_cents,
                     tax_lines: original_tax(ticket), bundle_tier: bundle)
    end
    if bundle.price_cents > was
      raise Error, "#{bundle.name} costs #{money(bundle.price_cents)} on #{target.show.date_and_time.strftime('%a %b %-d')}, " \
                   "more than the #{money(was)} they paid for theirs. Refund them instead and let them buy again."
    end

    price = TicketTier.split(bundle.price_cents, size).max
    discount = [ ticket.discount_cents, price ].min
    tax = TaxCalculator.for_ticket(target, base, price - discount)
    Row.new(ticket: ticket, tier: base, price_cents: price, discount_cents: discount, tax_lines: tax.lines, bundle_tier: bundle)
  end

  # The tax recorded when the ticket was bought (not refund reversals).
  def self.original_tax(ticket)
    ticket.tax_lines.select { |line| line.reversal_of_id.nil? && line.tax_cents >= 0 }
  end

  def self.share(cents, part, whole)
    whole.zero? ? 0 : (cents * part) / whole
  end

  def self.money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  end

  private_class_method :moved_cents, :create_order!, :retire_old_tickets!, :move_products!, :post_money!, :refund_difference!,
                       :row_for, :free_row, :bundle_for, :bundle_row, :original_tax, :share, :money, :check_seats!, :inventory_for
end

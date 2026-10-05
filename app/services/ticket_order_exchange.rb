# frozen_string_literal: true

# Moving a buyer's tickets to another date of the same production: the
# manager's "Move to another date" on an order. (Buyers can't do it
# themselves yet.)
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
# refused: refund them and let them buy again.
class TicketOrderExchange
  class Error < StandardError; end

  # One ticket and what it becomes.
  Row = Data.define(:ticket, :tier, :price_cents, :discount_cents, :tax_lines) do
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
  end

  # The other dates these tickets can move to: the same production, on sale,
  # still to come.
  def self.targets(order)
    listing = order.ticket_listing
    TicketListing.where(organization_id: order.organization_id, production_id: listing.production_id, status: "on_sale")
                 .where.not(id: listing.id).joins(:show).where(shows: { canceled: false })
                 .where("shows.date_and_time > ?", Time.current)
                 .includes(:ticket_tiers, show: %i[location location_space]).order("shows.date_and_time")
  end

  # Tickets that can move: held and not used yet.
  def self.movable(order)
    order.tickets.where(status: "valid").includes(:ticket_tier, :tax_lines).order(:id)
  end

  # What each ticket type becomes: the type with the same name, unless the
  # manager chose another.
  def self.tier_map(tickets, target, chosen = {})
    tiers = target.ticket_tiers.reject(&:archived_at)
    chosen = chosen.to_h.transform_keys(&:to_i)
    tickets.map(&:ticket_tier).uniq.to_h do |tier|
      pick = chosen[tier.id].presence&.to_i
      [ tier.id, pick || tiers.find { |t| t.name.casecmp?(tier.name) }&.id ]
    end
  end

  def self.plan(order, target:, ticket_ids: nil, chosen_tiers: {})
    raise Error, "Only a paid order's tickets can move." unless order.paid? && order.money_path.in?(%w[cocoscout none])
    raise Error, "This show has started, and refunds after the show are off, so its tickets can't move." unless TicketOrderRefund.allowed?(order)
    raise Error, "Choose another date to move them to." unless target && targets(order).exists?(id: target.id)

    tickets = movable(order).to_a
    tickets = tickets.select { |t| ticket_ids.map(&:to_i).include?(t.id) } if ticket_ids.present?
    raise Error, "Choose the tickets to move." if tickets.empty?

    map = tier_map(tickets, target, chosen_tiers)
    tiers = target.ticket_tiers.reject(&:archived_at).index_by(&:id)
    rows = tickets.map { |ticket| row_for(ticket, tiers[map[ticket.ticket_tier_id]], target) }
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

  def self.exchange!(order, target:, ticket_ids: nil, chosen_tiers: {}, by: nil, email_them: true)
    organization = order.organization
    listing = order.ticket_listing
    exchange = nil
    plan = nil
    OrgCashEntry.with_org_lock(organization) do
      order.with_lock do
        plan = plan(order, target: target, ticket_ids: ticket_ids, chosen_tiers: chosen_tiers)
        if listing.released_at.present? && plan.moved_cents > CocoScoutBalance.available_cents(organization)
          raise Error, "This show's money was already spent or withdrawn, so its tickets can't move to a show still to come."
        end

        requests = plan.rows.group_by(&:tier).transform_values(&:size)
        Ticketing::Inventory.reserve!(target, requests) do
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

  # The buyer, their payment and their share of the money, on the new date.
  def self.create_order!(order, plan)
    tickets = plan.tickets
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
      ticket = new_order.tickets.create!(ticket_tier: row.tier, ticket_listing: plan.target, status: "valid",
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
    LedgerPosting.post!(organization: order.organization, source: exchange, kind: "exchange", entry_date: Date.current,
                        memo: "Tickets #{order.code} moved to #{plan.target.display_title}, #{plan.target.show.date_and_time.strftime('%b %-d')}",
                        lines: [
                          { account: old_listing.released_at ? :ticket_income : :advance_ticket_sales, amount_cents: plan.old_face_cents, **from },
                          { account: :tax_to_remit, amount_cents: plan.old_tax_cents, **from },
                          { account: :advance_ticket_sales, amount_cents: -plan.old_face_cents, **to },
                          { account: :tax_to_remit, amount_cents: -plan.old_tax_cents, **to },
                          { account: old_listing.released_at ? :product_income : :advance_product_sales, amount_cents: moved_products, **from },
                          { account: :advance_product_sales, amount_cents: -moved_products, **to }
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
    raise Error, "Choose what #{ticket.ticket_tier.name} tickets become on the new date." unless tier
    if tier.price_cents > ticket.price_cents
      raise Error, "#{tier.name} costs #{money(tier.price_cents)} on #{target.show.date_and_time.strftime('%a %b %-d')}, " \
                   "more than their #{money(ticket.price_cents)} ticket. Refund them instead and let them buy again."
    end
    return Row.new(ticket: ticket, tier: tier, price_cents: ticket.price_cents, discount_cents: ticket.discount_cents, tax_lines: original_tax(ticket)) if tier.price_cents == ticket.price_cents

    discount = [ ticket.discount_cents, tier.price_cents ].min
    tax = TaxCalculator.for_ticket(target, tier, tier.price_cents - discount)
    Row.new(ticket: ticket, tier: tier, price_cents: tier.price_cents, discount_cents: discount, tax_lines: tax.lines)
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
                       :row_for, :original_tax, :share, :money
end

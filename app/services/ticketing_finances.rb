# frozen_string_literal: true

# CocoScout's own take from ticketing, for superadmin Finances: our 50¢ per
# paid ticket (less what refunds waived), the card processing we charged
# buyers or theaters against what Stripe actually took (the margin or the
# loss on it), by period and by organization. Stripe's real fee arrives a
# little after each sale (BackfillStripeFeeJob), so a count of orders still
# waiting on it is part of the picture.
class TicketingFinances
  Totals = Data.define(:orders, :tickets, :gross_cents, :platform_fee_cents, :waived_cents, :processing_charged_cents,
                       :stripe_fee_cents, :missing_fee_count) do
    def fees_earned_cents = platform_fee_cents - waived_cents
    def processing_margin_cents = processing_charged_cents - stripe_fee_cents
    def net_cents = fees_earned_cents + processing_margin_cents
  end
  OrgRow = Data.define(:organization, :totals)

  def initialize(range = nil)
    @range = range
  end

  def totals
    @totals ||= totals_for(orders, refunds)
  end

  def by_organization
    @by_organization ||= orders.group_by(&:organization_id).map do |org_id, rows|
      ids = rows.map(&:id).to_set
      OrgRow.new(organization: organizations.fetch(org_id), totals: totals_for(rows, refunds.select { |r| ids.include?(r.ticket_order_id) }))
    end.sort_by { |row| -row.totals.fees_earned_cents }
  end

  private

  # Orders paid through CocoScout in the period (cash and comps earn nothing).
  def orders
    @orders ||= begin
      scope = TicketOrder.where(status: TicketOrder::WAS_PAID, money_path: "cocoscout")
      scope = scope.where(paid_at: @range) if @range
      scope.to_a
    end
  end

  def refunds
    @refunds ||= TicketRefund.succeeded.where(ticket_order_id: orders.map(&:id)).to_a
  end

  def organizations
    @organizations ||= Organization.where(id: orders.map(&:organization_id).uniq).index_by(&:id)
  end

  def ticket_counts
    @ticket_counts ||= Ticket.where(ticket_order_id: orders.map(&:id), status: Ticket::SOLD_STATUSES).group(:ticket_order_id).count
  end

  # An exchange makes a second order that restates the moved tickets' share
  # of the original payment; the money was charged once, on the original. So
  # money comes from orders that started life as a purchase, while tickets
  # (the moved ones are only valid on the new order) and refunds (a refund
  # on a moved ticket is against the new order) come from every order.
  def totals_for(rows, row_refunds)
    paid = rows.reject(&:exchanged_from_id)
    Totals.new(
      orders: paid.size,
      tickets: rows.sum { |o| ticket_counts.fetch(o.id, 0) },
      gross_cents: paid.sum(&:total_cents),
      platform_fee_cents: paid.sum(&:platform_fee_cents),
      waived_cents: row_refunds.sum(&:platform_fee_waived_cents),
      processing_charged_cents: paid.sum(&:processing_cents),
      stripe_fee_cents: paid.sum { |o| o.stripe_fee_cents.to_i },
      missing_fee_count: paid.count { |o| o.stripe_fee_cents.nil? && o.total_cents.positive? }
    )
  end
end

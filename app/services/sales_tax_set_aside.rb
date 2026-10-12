# frozen_string_literal: true

# Sales tax kept out of what payout runs, refunds and withdrawals can spend
# (Tim, 2026-10-12: "set aside by default"). The organization owes it to the
# government, so CocoScout holds it apart until the organization marks the
# period paid on the Sales tax page.
#
# Counted, from the tax lines (net of refunds and moves), only where the
# money is really in the CocoScout balance and spendable otherwise:
#
#   tickets and products — paid through CocoScout (not cash at the door), for
#                          a show that has happened and settled; before that
#                          the whole sale is already held for its show
#   course registrations — paid by card, once settled, and only when the
#                          organization pools (otherwise the money rides the
#                          payout run to its own bank, tax and all)
#   credit passes        — once the pass has ended and its money is theirs
#
# Only tax collected on or after organizations.sales_tax_set_aside_since
# counts (a refund's line goes by its original sale), and none from a period
# marked paid for that tax (SalesTaxRemittance, by sale or show date).
class SalesTaxSetAside
  def self.on?(organization)
    organization.sales_tax_set_aside_since.present?
  end

  def self.cents(organization)
    return 0 unless on?(organization)

    [ sum(organization), 0 ].max
  end

  # What's set aside, by the month each tax line landed in, oldest first:
  # [[Date (first of month), cents], …], months that net to zero left out.
  def self.by_month(organization)
    return [] unless on?(organization)

    parts(organization, select: "date_trunc('month', tl.sale_date)::date AS month, SUM(tl.tax_cents) AS cents", group: "1")
      .flat_map { |sql| TaxLine.connection.select_rows(sql) }
      .each_with_object(Hash.new(0)) { |(month, cents), totals| totals[month.to_date] += cents.to_i }
      .reject { |_, cents| cents.zero? }.sort.to_a
  end

  # How much less is set aside once these tickets and products are refunded
  # or moved: their tax goes back to the buyer (or to the new show), so the
  # refund may spend it. At most what's set aside now.
  def self.relief_cents(organization, ticket_ids: [], item_ids: [])
    return 0 unless on?(organization)
    return 0 if ticket_ids.blank? && item_ids.blank?

    found = []
    found << part(organization, :tickets, relief_ids: ticket_ids, select: "COALESCE(SUM(tl.tax_cents), 0)") if ticket_ids.present?
    found << part(organization, :products, relief_ids: item_ids, select: "COALESCE(SUM(tl.tax_cents), 0)") if item_ids.present?
    relief = found.sum { |sql| TaxLine.connection.select_value(sql).to_i }
    relief.clamp(0, cents(organization))
  end

  def self.sum(organization)
    parts(organization, select: "COALESCE(SUM(tl.tax_cents), 0)").sum { |sql| TaxLine.connection.select_value(sql).to_i }
  end

  def self.parts(organization, select:, group: nil)
    kinds = %i[tickets products passes]
    kinds << :courses if CocoScoutBalance.pooled?(organization)
    kinds.map { |kind| part(organization, kind, select: select, group: group) }
  end

  # One kind of taxed thing, as SQL. relief_ids: instead of everything set
  # aside, the original lines on these taxables that a refund is about to
  # reverse, as their reversals (dated today) would count.
  def self.part(organization, kind, select:, group: nil, relief_ids: nil)
    join, where = case kind
    when :tickets
      [ "JOIN tickets t ON tl.taxable_type = 'Ticket' AND t.id = tl.taxable_id " \
        "JOIN ticket_orders o ON o.id = t.ticket_order_id JOIN ticket_listings l ON l.id = o.ticket_listing_id",
        "o.money_path = 'cocoscout' AND o.status IN (:was_paid) AND l.released_at IS NOT NULL AND o.paid_at <= :settled" ]
    when :products
      [ "JOIN ticket_order_items i ON tl.taxable_type = 'TicketOrderItem' AND i.id = tl.taxable_id " \
        "JOIN ticket_orders o ON o.id = i.ticket_order_id JOIN ticket_listings l ON l.id = o.ticket_listing_id",
        "o.money_path = 'cocoscout' AND o.status IN (:was_paid) AND l.released_at IS NOT NULL AND o.paid_at <= :settled" ]
    when :courses
      [ "JOIN course_registrations cr ON tl.taxable_type = 'CourseRegistration' AND cr.id = tl.taxable_id",
        "cr.stripe_payment_intent_id IS NOT NULL AND cr.status IN ('confirmed', 'refunded') AND cr.paid_at <= :settled" ]
    when :passes
      [ "JOIN ticket_pass_holdings h ON tl.taxable_type = 'TicketPassHolding' AND h.id = tl.taxable_id",
        "h.status = 'ended'" ]
    end

    if relief_ids
      sold_on = "tl.sale_date"
      sale_basis_date = ":today"
      scope = "tl.taxable_id IN (:ids) AND tl.reversal_of_id IS NULL AND tl.tax_cents >= 0 " \
              "AND NOT EXISTS (SELECT 1 FROM tax_lines rev WHERE rev.reversal_of_id = tl.id)"
    else
      sold_on = "COALESCE(orig.sale_date, tl.sale_date)"
      sale_basis_date = "tl.sale_date"
      scope = "TRUE"
    end

    sql = <<~SQL.squish
      SELECT #{select}
      FROM tax_lines tl
      LEFT JOIN tax_lines orig ON orig.id = tl.reversal_of_id
      #{join}
      WHERE tl.organization_id = :organization_id AND tl.remitter = 'organization'
        AND #{where} AND #{scope}
        AND #{sold_on} >= :since
        AND NOT EXISTS (
          SELECT 1 FROM sales_tax_remittances r
          WHERE r.organization_id = tl.organization_id AND r.tax_name = tl.name AND r.rate_bps = tl.rate_bps
            AND (CASE r.basis WHEN 'event' THEN tl.event_date ELSE #{sale_basis_date} END) BETWEEN r.period_start AND r.period_end
        )
      #{"GROUP BY #{group}" if group}
    SQL
    TaxLine.sanitize_sql([ sql, { organization_id: organization.id, was_paid: TicketOrder::WAS_PAID,
                                  settled: TicketBalance::SETTLE_AFTER.ago, since: organization.sales_tax_set_aside_since,
                                  today: Date.current, ids: Array(relief_ids).presence || [ 0 ] } ])
  end

  private_class_method :sum, :parts, :part
end

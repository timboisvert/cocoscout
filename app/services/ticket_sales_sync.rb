# frozen_string_literal: true

# Keeps a show's financials honest about what CocoScout sold: one "CocoScout
# Tickets" row on its ticket sales (Show Financials), counting paid tickets
# and their face value — never fees or tax. Contract settlements read the
# totals those rows add up to, so a revenue split settles off real sales with
# nobody typing them in.
#
# Products bought with the tickets (bottles) go where the theater said: a
# product that counts as ticket revenue joins the row's amount, so a split
# sees it; any other is a "CocoScout products" line in other revenue, so the
# show's net is right but no split ever touches it.
class TicketSalesSync
  SOURCE_KEY = "cocoscout"
  SOURCE_NAME = "CocoScout Tickets"
  PRODUCTS_LABEL = "CocoScout products"

  def self.source_for(organization)
    organization.ticket_sources.find_by(system_key: SOURCE_KEY) ||
      organization.ticket_sources.create!(name: SOURCE_NAME, system_key: SOURCE_KEY, position: -1)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # A source the org named "CocoScout Tickets" itself becomes the built-in one.
    source = organization.ticket_sources.find_by!(name: SOURCE_NAME)
    source.update!(system_key: SOURCE_KEY)
    source
  end

  def self.sync!(show)
    listing = show.ticket_listing
    return unless listing

    paid = Ticket.joins(:ticket_order)
                 .where(ticket_listing_id: listing.id, status: Ticket::SOLD_STATUSES)
                 .where(ticket_orders: { money_path: %w[cocoscout cash] })
                 .where("tickets.price_cents > tickets.discount_cents")
    count = paid.count
    included_tax = TaxLine.where(taxable_type: "Ticket", taxable_id: paid.select(:id), included: true).sum(:tax_cents)
    face_cents = paid.sum("tickets.price_cents - tickets.discount_cents") - included_tax

    counted, other = product_face_cents(listing)

    source = source_for(show.production.organization)
    financials = show.show_financials || show.create_show_financials!(revenue_type: "ticket_sales")
    line = financials.ticket_sales_lines.find_or_initialize_by(ticket_source: source)
    if count.zero? && counted.zero?
      line.destroy! if line.persisted?
    else
      line.update!(tickets_sold: count, amount: (face_cents + counted) / 100.0)
    end
    sync_other_revenue!(financials, other)
  end

  # Face value of the products sold for this show (no fees, no tax), split
  # into what counts as ticket revenue and what doesn't.
  def self.product_face_cents(listing)
    items = TicketOrderItem.joins(:ticket_order)
                           .where(ticket_listing_id: listing.id, status: TicketOrderItem::SOLD_STATUSES)
                           .where(ticket_orders: { money_path: %w[cocoscout cash] })
    included_tax = TaxLine.where(taxable_type: "TicketOrderItem", taxable_id: items.select(:id), included: true)
                          .joins("JOIN ticket_order_items ON ticket_order_items.id = tax_lines.taxable_id")
                          .group("ticket_order_items.counts_toward_ticket_revenue").sum(:tax_cents)
    face = items.group(:counts_toward_ticket_revenue).sum("unit_price_cents * quantity")
    [ face.fetch(true, 0) - included_tax.fetch(true, 0), face.fetch(false, 0) - included_tax.fetch(false, 0) ]
  end

  # The one "CocoScout products" entry among the show's other revenue, kept
  # in step; the theater's own entries are left alone.
  def self.sync_other_revenue!(financials, cents)
    details = financials.normalized_other_revenue_details.reject { |item| item.is_a?(Hash) && item["description"] == PRODUCTS_LABEL }
    details << { "description" => PRODUCTS_LABEL, "amount" => cents / 100.0 } if cents.positive?
    return if details == financials.normalized_other_revenue_details

    financials.update_columns(other_revenue_details: details, updated_at: Time.current)
  end
end

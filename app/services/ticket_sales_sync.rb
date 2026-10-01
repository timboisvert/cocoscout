# frozen_string_literal: true

# Keeps a show's financials honest about what CocoScout sold: one "CocoScout
# Tickets" row on its ticket sales (Show Financials), counting paid tickets
# and their face value — never fees or tax. Contract settlements read the
# totals those rows add up to, so a revenue split settles off real sales with
# nobody typing them in.
class TicketSalesSync
  SOURCE_KEY = "cocoscout"
  SOURCE_NAME = "CocoScout Tickets"

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

    source = source_for(show.production.organization)
    financials = show.show_financials || show.create_show_financials!(revenue_type: "ticket_sales")
    line = financials.ticket_sales_lines.find_or_initialize_by(ticket_source: source)
    if count.zero?
      line.destroy! if line.persisted?
    else
      line.update!(tickets_sold: count, amount: face_cents / 100.0)
    end
  end
end

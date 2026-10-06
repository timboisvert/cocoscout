# frozen_string_literal: true

# Tickets sold on other sites, as the theater types them on a show's page:
# per site and ticket type, a count (and the money, when they have it).
#
#   record!       saves one show's rows for the sites in the form, then feeds
#                 each site's Show Financials line from them, so settlement
#                 already has the numbers. A site cleared to nothing loses
#                 its row and its line.
#   fed_source_ids the sites whose financials line comes from here, which
#                 the worksheet shows but doesn't let anyone type over.
class TicketOutsideSales
  # rows: { source_id => { tier_id => { "tickets" => "6", "amount" => "$120" } } }
  def self.record!(listing, rows)
    organization = listing.organization
    tiers = listing.ticket_tiers.active.reject(&:bundle?).index_by(&:id)
    sources = organization.ticket_sources.hand_made.active.where(id: rows.keys).index_by(&:id)
    ActiveRecord::Base.transaction do
      rows.each do |source_id, by_tier|
        source = sources[source_id.to_i] or next
        by_tier.to_h.each do |tier_id, cells|
          tier = tiers[tier_id.to_i] or next
          tickets = cells["tickets"].to_i
          cents = dollars_to_cents(cells["amount"])
          row = listing.ticket_outside_sales.find_or_initialize_by(ticket_tier: tier, ticket_source: source)
          if tickets.zero? && cents.zero?
            row.destroy! if row.persisted?
          else
            row.update!(organization: organization, tickets_sold: tickets, amount_cents: cents)
          end
        end
        sync_source!(listing, source)
      end
    end
  end

  # A site's Show Financials row is what it sold here, every type added up:
  # the row the worksheet would show, fed from the show's page instead.
  def self.sync_source!(listing, source)
    rows = listing.ticket_outside_sales.where(ticket_source: source)
    financials = listing.show.show_financials || listing.show.create_show_financials!(revenue_type: "ticket_sales")
    line = financials.ticket_sales_lines.find_or_initialize_by(ticket_source: source)
    if rows.none?
      line.destroy! if line.persisted?
    else
      line.update!(tickets_sold: rows.sum(:tickets_sold), amount: rows.sum(:amount_cents) / 100.0)
    end
  end

  def self.fed_source_ids(show)
    listing_id = show.ticket_listing&.id
    return [] unless listing_id

    TicketOutsideSale.where(ticket_listing_id: listing_id).distinct.pluck(:ticket_source_id)
  end

  def self.dollars_to_cents(text)
    cleaned = text.to_s.delete("$,").strip
    cleaned.empty? ? 0 : (BigDecimal(cleaned) * 100).round.to_i
  rescue ArgumentError
    0
  end
end

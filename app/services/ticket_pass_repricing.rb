# frozen_string_literal: true

# What returning part of a pass costs the buyer (Tim, 2026-10-05): the shows
# they keep go back to their regular price, so a pass bought for its discount
# and half returned is no cheaper than the half bought alone. For each pass
# ticket returned, one of the same pass's tickets at every other show in the
# purchase (the same person's, as far as anyone can tell) loses its saving,
# and the tax on the saving with it. Never more than the returned tickets
# would have given back: a buyer is never asked for money.
#
# The saving stays with the kept show (its ticket now carries its regular
# price), so a later refund of that show gives its regular price back and the
# whole pass always refunds in full.
class TicketPassRepricing
  Reprice = Data.define(:ticket, :saving_cents, :tax) do
    # What the buyer doesn't get back for this kept ticket: the saving and
    # any tax added on top of it.
    def cents
      saving_cents + tax.added_cents
    end
  end

  # tickets: the tickets being refunded from this order.
  def self.for(order, tickets)
    returned = tickets.select(&:ticket_pass_id)
    return [] if returned.empty? || order.ticket_purchase_id.nil?

    room = returned.sum { |t| t.price_cents - t.discount_cents + t.tax_lines.reject(&:included).sum(&:tax_cents) }
    siblings = order.ticket_purchase.ticket_orders.where.not(id: order.id).includes(:ticket_listing).to_a
    reprices = []
    returned.group_by(&:ticket_pass_id).each do |pass_id, rows|
      siblings.each do |sibling|
        sibling.tickets.where(ticket_pass_id: pass_id, status: Ticket::SOLD_STATUSES).where("discount_cents > 0")
               .includes(:ticket_tier).order(:id).limit(rows.size).each do |kept|
          reprice = fit(sibling.ticket_listing, kept, kept.discount_cents, room)
          break unless reprice

          reprices << reprice
          room -= reprice.cents
        end
      end
    end
    reprices
  end

  # The largest saving (up to the ticket's own) whose cost fits what's left
  # to take from the refund.
  def self.fit(listing, ticket, saving, room)
    return nil unless room.positive?

    saving = [ saving, room ].min
    tax = TaxCalculator.for_ticket(listing, ticket.ticket_tier, saving)
    while saving.positive? && saving + tax.added_cents > room
      saving -= 1
      tax = TaxCalculator.for_ticket(listing, ticket.ticket_tier, saving)
    end
    saving.positive? ? Reprice.new(ticket: ticket, saving_cents: saving, tax: tax) : nil
  end

  # The kept tickets go back to regular: less discount, the saving's tax
  # recorded like a sale's.
  def self.apply!(refund)
    Array(refund.repriced).each do |entry|
      ticket = Ticket.includes(:ticket_tier, :ticket_listing).find(entry["ticket_id"])
      saving = entry["saving_cents"].to_i
      tax = TaxCalculator.for_ticket(ticket.ticket_listing, ticket.ticket_tier, saving)
      tax.lines.each do |line|
        TaxLine.create!(organization_id: refund.organization_id, taxable: ticket, tax_rate: line.tax_rate,
                        name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                        included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                        base_cents: line.base_cents, tax_cents: line.tax_cents,
                        sale_date: Date.current, event_date: ticket.ticket_listing.starts_at&.to_date)
      end
      ticket.update_columns(discount_cents: ticket.discount_cents - saving, tax_cents: ticket.tax_cents + tax.tax_cents, updated_at: Time.current)
    end
  end

  # Books lines for the kept shows: each one's sales (or income, once it has
  # happened) and tax go up by what the buyer didn't get back.
  def self.book_lines(refund)
    Array(refund.repriced).group_by { |entry| entry["ticket_listing_id"] }.flat_map do |listing_id, entries|
      listing = TicketListing.includes(:show, :production).find(listing_id)
      dims = { show: listing.show, production: listing.production }
      income = listing.released_at.present? ? :ticket_income : :advance_ticket_sales
      [
        { account: income, amount_cents: -entries.sum { |e| e["saving_cents"].to_i - e["included_tax_cents"].to_i }, **dims },
        { account: :tax_to_remit, amount_cents: -entries.sum { |e| e["included_tax_cents"].to_i + e["added_tax_cents"].to_i }, **dims }
      ]
    end
  end

  def self.listings(refund)
    TicketListing.where(id: Array(refund.repriced).map { |entry| entry["ticket_listing_id"] }.uniq).includes(:show)
  end

  private_class_method :fit
end

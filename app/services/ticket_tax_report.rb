# frozen_string_literal: true

# Taxes collected on tickets, ready for filing: for a month or quarter, by
# sale date or show date, one row per tax (name and rate) with gross
# receipts, exempt and taxable receipts, the tax collected, the tax given back
# on refunds, and what's left to pay. Built from tax_lines, which snapshot the
# rate on every sale, so changing the rate never rewrites a past period.
# Only tax on orders that were actually paid counts (checkouts nobody paid
# for leave lines behind).
class TicketTaxReport
  Row = Data.define(:name, :rate_bps, :jurisdiction, :gross_cents, :exempt_cents, :taxable_cents,
                    :collected_cents, :refunded_cents) do
    def net_cents
      collected_cents + refunded_cents
    end

    def rate_label
      "#{format('%g', rate_bps / 100.0)}%"
    end
  end

  BASES = %w[sale event].freeze
  KINDS = %w[all tickets courses].freeze

  attr_reader :from, :to, :basis, :kind

  # kind: "tickets", "courses", or "all" (both).
  def initialize(organization, from:, to:, basis: "sale", kind: "all")
    @organization = organization
    @from = from
    @to = to
    @basis = BASES.include?(basis) ? basis : "sale"
    @kind = KINDS.include?(kind) ? kind : "all"
  end

  def rows
    @rows ||= lines.group_by { |line| [ line.name, line.rate_bps, line.jurisdiction ] }.map do |(name, rate, jurisdiction), group|
      originals = group.reject { |l| l.reversal_of_id }
      reversals = group.select(&:reversal_of_id)
      exempt = originals.select(&:exempt).sum(&:base_cents) + reversals.select(&:exempt).sum(&:base_cents)
      gross = group.sum(&:base_cents)
      Row.new(name: name, rate_bps: rate, jurisdiction: jurisdiction, gross_cents: gross, exempt_cents: exempt,
              taxable_cents: gross - exempt, collected_cents: originals.sum(&:tax_cents),
              refunded_cents: reversals.sum(&:tax_cents))
    end.sort_by { |row| [ row.name, row.rate_bps ] }
  end

  def total_net_cents
    rows.sum(&:net_cents)
  end

  def to_csv
    require "csv"
    dollars = ->(cents) { format("%.2f", cents / 100.0) }
    CSV.generate do |csv|
      csv << [ "Tax", "Rate", "Jurisdiction", "Gross receipts", "Exempt receipts", "Taxable receipts",
               "Tax collected", "Tax refunded", "Net tax" ]
      rows.each do |row|
        csv << [ row.name, row.rate_label, row.jurisdiction, dollars.call(row.gross_cents), dollars.call(row.exempt_cents),
                 dollars.call(row.taxable_cents), dollars.call(row.collected_cents), dollars.call(row.refunded_cents),
                 dollars.call(row.net_cents) ]
      end
    end
  end

  private

  def lines
    date_column = basis == "event" ? :event_date : :sale_date
    base = TaxLine.where(organization_id: @organization.id, remitter: "organization").where(date_column => from..to)
    found = []
    if kind != "courses"
      found += base.where(taxable_type: "Ticket")
                   .joins("JOIN tickets ON tickets.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = tickets.ticket_order_id")
                   .where(ticket_orders: { status: TicketOrder::WAS_PAID }).to_a
      found += base.where(taxable_type: "TicketOrderItem")
                   .joins("JOIN ticket_order_items ON ticket_order_items.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = ticket_order_items.ticket_order_id")
                   .where(ticket_orders: { status: TicketOrder::WAS_PAID }).to_a
    end
    if kind != "tickets"
      found += base.where(taxable_type: "CourseRegistration")
                   .joins("JOIN course_registrations ON course_registrations.id = tax_lines.taxable_id")
                   .where(course_registrations: { status: %w[confirmed refunded] }).to_a
    end
    found
  end
end

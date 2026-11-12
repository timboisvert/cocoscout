# frozen_string_literal: true

# Taxes collected on tickets, ready for filing: for a month or quarter, by
# sale date or show date, one row per tax (name and rate) with gross
# receipts, exempt and taxable receipts, the tax collected, the tax given back
# on refunds, and what's left to pay. Built from tax_lines, which snapshot the
# rate on every sale, so changing the rate never rewrites a past period.
# Only tax on orders that were actually paid counts (checkouts nobody paid
# for leave lines behind).
#
# There is a tax line for every ticket, so a quarter is added up in the
# database, a row per tax, and never read line by line.
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
    @rows ||= sums.map do |(name, rate, jurisdiction), sum|
      Row.new(name: name, rate_bps: rate, jurisdiction: jurisdiction, gross_cents: sum[:gross], exempt_cents: sum[:exempt],
              taxable_cents: sum[:gross] - sum[:exempt], collected_cents: sum[:collected], refunded_cents: sum[:refunded])
    end.sort_by { |row| [ row.name, row.rate_bps, row.jurisdiction.to_s ] }
  end

  def total_net_cents
    rows.sum(&:net_cents)
  end

  # The part of it collected in cash at the door: it's in the organization's
  # cash box already, so it's never set aside in the CocoScout balance.
  def cash_tax_cents
    sums.values.sum { |sum| sum[:cash] }
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

  # { [name, rate_bps, jurisdiction] => { gross:, exempt:, collected:, refunded:, cash: } }
  # A refund's lines (reversal_of_id) carry negative amounts: they come off
  # gross and exempt, and their tax is what was given back.
  def sums
    return @sums if @sums

    date_column = basis == "event" ? :event_date : :sale_date
    base = TaxLine.where(organization_id: @organization.id, remitter: "organization").where(date_column => from..to)
    scopes = []
    if kind != "courses"
      paid = { ticket_orders: { status: TicketOrder::WAS_PAID } }
      scopes << [ base.where(taxable_type: "Ticket").where(paid)
                      .joins("JOIN tickets ON tickets.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = tickets.ticket_order_id"), true ]
      scopes << [ base.where(taxable_type: "TicketOrderItem").where(paid)
                      .joins("JOIN ticket_order_items ON ticket_order_items.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = ticket_order_items.ticket_order_id"), true ]
    end
    if kind != "tickets"
      scopes << [ base.where(taxable_type: "CourseRegistration")
                      .joins("JOIN course_registrations ON course_registrations.id = tax_lines.taxable_id")
                      .where(course_registrations: { status: %w[confirmed refunded] }), false ]
    end
    @sums = Hash.new { |hash, key| hash[key] = { gross: 0, exempt: 0, collected: 0, refunded: 0, cash: 0 } }
    scopes.each do |scope, has_orders|
      cash = has_orders ? "COALESCE(SUM(tax_lines.tax_cents) FILTER (WHERE ticket_orders.money_path = 'cash'), 0)" : "0"
      scope.group("tax_lines.name", "tax_lines.rate_bps", "tax_lines.jurisdiction").pluck(
        Arel.sql("tax_lines.name"), Arel.sql("tax_lines.rate_bps"), Arel.sql("tax_lines.jurisdiction"),
        Arel.sql("COALESCE(SUM(tax_lines.base_cents), 0)"),
        Arel.sql("COALESCE(SUM(tax_lines.base_cents) FILTER (WHERE tax_lines.exempt), 0)"),
        Arel.sql("COALESCE(SUM(tax_lines.tax_cents) FILTER (WHERE tax_lines.reversal_of_id IS NULL), 0)"),
        Arel.sql("COALESCE(SUM(tax_lines.tax_cents) FILTER (WHERE tax_lines.reversal_of_id IS NOT NULL), 0)"),
        Arel.sql(cash)
      ).each do |name, rate, jurisdiction, gross, exempt, collected, refunded, in_cash|
        sum = @sums[[ name, rate, jurisdiction ]]
        sum[:gross] += gross.to_i
        sum[:exempt] += exempt.to_i
        sum[:collected] += collected.to_i
        sum[:refunded] += refunded.to_i
        sum[:cash] += in_cash.to_i
      end
    end
    @sums
  end
end

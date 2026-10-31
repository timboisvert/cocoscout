# frozen_string_literal: true

# Tax on tickets other sites sold, where the organization owes it (the
# source says "we owe the tax"): the amount typed for a source's line is
# what arrived, tax included, so the tax is carved out at the
# organization's ticket tax rate and sits in Tax to pay the government.
# That money is in the bank, not set aside in the CocoScout balance.
class OutsideTicketTax
  Row = Data.define(:source, :sales_cents, :tax_cents, :shows)

  def self.rate_bps(organization)
    rule = organization.tax_rules.find_by(money_kind: "tickets", scope_type: nil)
    rule&.tax_rates&.current&.order(:id)&.first&.rate_bps.to_i
  end

  # Tax inside a tax-inclusive amount at the organization's rate.
  def self.tax_cents(organization, amount_cents)
    bps = rate_bps(organization)
    return 0 if bps.zero? || amount_cents.to_i.zero?

    (amount_cents.to_i * bps / (10_000.0 + bps)).round
  end

  # What a show's financials owe in outside tax: the "we owe" lines only.
  def self.for_financials(organization, financials)
    financials.ticket_sales_lines.includes(:ticket_source).sum do |line|
      line.ticket_source&.we_owe_tax? ? tax_cents(organization, (line.amount.to_f * 100).round) : 0
    end
  end

  # By source, for shows dated in a period (an outside sale only has a show date).
  def self.rows(organization, from:, to:)
    lines = TicketSalesLine.joins(:ticket_source, show_financials: :show)
                           .where(ticket_sources: { organization_id: organization.id, tax_handling: "we_owe" })
                           .where(shows: { canceled: false, date_and_time: from.beginning_of_day..to.end_of_day })
                           .includes(:ticket_source)
    lines.group_by(&:ticket_source).map do |source, group|
      sales = group.sum { |l| (l.amount.to_f * 100).round }
      Row.new(source: source, sales_cents: sales, tax_cents: group.sum { |l| tax_cents(organization, (l.amount.to_f * 100).round) }, shows: group.map(&:show_financials_id).uniq.size)
    end.sort_by { |r| r.source.name }
  end

  # Everything the books should carry, for the reconciliation: every posted
  # financials' outside tax.
  def self.owed_total_cents(organization)
    ids = TicketSalesLine.joins(:ticket_source).where(ticket_sources: { organization_id: organization.id, tax_handling: "we_owe" }).distinct.pluck(:show_financials_id)
    ShowFinancials.where(id: ids).includes(:ticket_sales_lines, show: :production).sum do |f|
      BooksOutsidePoster.outside_ticket_cents(f, f.show).zero? ? 0 : for_financials(organization, f)
    end
  end
end

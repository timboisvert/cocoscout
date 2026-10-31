# frozen_string_literal: true

# Checks an organization's books against the detailed records they summarize,
# so a posting that was missed (or posted twice) shows up the next morning
# instead of in a tax filing. Each check compares one account with what it
# should equal, now that every row of both sub-ledgers posts (stage B):
#
#   CocoScout balance — the cash ledger, every row (sales, refunds, course
#                       money, contract money, run funding, payees paid,
#                       withdrawals, corrections).
#   Owed to payees    — the payout ledger, every row.
#   Tax to remit      — the tax lines on paid tickets and on course
#                       registrations, less their reversals and less what
#                       the organization marked paid (SalesTaxRemittance).
#
# Returns the mismatches; none means the books agree.
class BooksReconciliation
  Mismatch = Data.define(:account, :books_cents, :expected_cents) do
    def difference_cents
      books_cents - expected_cents
    end
  end

  # Financials against Books, production by production, for a period: the
  # Money hub's gross revenue and cost of shows against the books' income
  # and spending for the same lines. Only where they differ. Two numbers
  # never disagree silently (plan C0).
  Disagreement = Data.define(:production, :financials_in_cents, :books_in_cents, :financials_out_cents, :books_out_cents)

  def self.financials_vs_books(organization, period_key: "this_month")
    productions = organization.productions.active.order(:name).to_a
    return [] if productions.empty?

    hub_period = { "this_month" => :this_month, "last_month" => :last_month, "this_quarter" => :this_quarter,
                   "this_year" => :this_year, "last_year" => :last_year, "all_time" => :all_time }.fetch(period_key.to_s, :this_month)
    hub = FinancialSummaryService.summaries_by_production(productions, hub_period)[:by_production]
    books = BooksReport.new(organization).overview(range: BooksReport.period_range(period_key)).productions.index_by { |r| r.production&.id }
    productions.filter_map do |production|
      h = hub[production.id]
      b = books[production.id]
      next if h.nil? && b.nil?

      fin_in = ((h&.dig(:gross_revenue) || 0) * 100).round
      fin_out = ((h&.dig(:cost_of_shows) || 0) * 100).round
      next if fin_in == b&.in_cents.to_i && fin_out == b&.out_cents.to_i

      Disagreement.new(production: production, financials_in_cents: fin_in, books_in_cents: b&.in_cents.to_i,
                       financials_out_cents: fin_out, books_out_cents: b&.out_cents.to_i)
    end
  end

  def self.check(organization)
    [ balance_check(organization), owed_check(organization), tax_check(organization) ].compact
  end

  def self.balance_check(organization)
    books = ChartOfAccounts.account(organization, :cocoscout_balance).natural_balance_cents
    expected = OrgCashEntry.where(organization: organization).sum(:amount_cents)
    Mismatch.new(account: "cocoscout_balance", books_cents: books, expected_cents: expected) unless books == expected
  end

  def self.owed_check(organization)
    books = ChartOfAccounts.account(organization, :owed_to_payees).natural_balance_cents
    expected = PayoutLedgerEntry.where(organization: organization).sum(:amount_cents)
    Mismatch.new(account: "owed_to_payees", books_cents: books, expected_cents: expected) unless books == expected
  end

  def self.tax_check(organization)
    books = ChartOfAccounts.account(organization, :tax_to_remit).natural_balance_cents
    tickets = TaxLine.where(organization_id: organization.id, taxable_type: "Ticket", remitter: "organization")
                     .joins("JOIN tickets ON tickets.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = tickets.ticket_order_id")
                     .where(ticket_orders: { status: TicketOrder::WAS_PAID, money_path: %w[cocoscout cash] })
                     .sum(:tax_cents)
    products = TaxLine.where(organization_id: organization.id, taxable_type: "TicketOrderItem", remitter: "organization")
                      .joins("JOIN ticket_order_items ON ticket_order_items.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = ticket_order_items.ticket_order_id")
                      .where(ticket_orders: { status: TicketOrder::WAS_PAID, money_path: %w[cocoscout cash] })
                      .sum(:tax_cents)
    courses = TaxLine.where(organization_id: organization.id, taxable_type: "CourseRegistration", remitter: "organization")
                     .joins("JOIN course_registrations ON course_registrations.id = tax_lines.taxable_id")
                     .where.not(course_registrations: { stripe_payment_intent_id: nil })
                     .sum(:tax_cents)
    passes = TaxLine.where(organization_id: organization.id, taxable_type: "TicketPassHolding", remitter: "organization")
                    .joins("JOIN ticket_pass_holdings ON ticket_pass_holdings.id = tax_lines.taxable_id")
                    .where(ticket_pass_holdings: { status: %w[active ended] })
                    .sum(:tax_cents)
    # Less what the organization has marked paid to the government.
    paid = SalesTaxRemittance.where(organization_id: organization.id).sum(:amount_cents)
    expected = tickets + products + courses + passes - paid
    Mismatch.new(account: "tax_to_remit", books_cents: books, expected_cents: expected) unless books == expected
  end

  private_class_method :balance_check, :owed_check, :tax_check
end

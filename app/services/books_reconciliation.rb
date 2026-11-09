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

    # Compared through today: a show still ahead this month has presales
    # Financials already count, which the books hold as tickets sold for
    # upcoming shows until the day after the show (2026-11-02).
    range = BooksReport.period_range(period_key)
    range = range.begin..[ range.end, Time.current.end_of_day ].min if range && range.end > Time.current
    hub = FinancialSummaryService.summaries_by_production_in(productions, range)[:by_production]
    books = BooksReport.new(organization).overview(range: range).productions.index_by { |r| r.production&.id }
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

  # The checks, run now and kept on the organization, so a page can say how
  # they stand without running them (Tim, 2026-11-09: every Books page ran
  # all of them, sums over every sale ever, to draw one line). The nightly
  # job and the Checks page keep it fresh.
  def self.record!(organization)
    mismatches = check(organization)
    organization.update_column(:books_check, { "at" => Time.current.iso8601, "mismatches" => mismatches.map { |m| m.to_h.stringify_keys } }
                                               .merge(kept(organization).slice("alerted")))
    mismatches
  end

  # What's kept, read from the row: the organization in hand may have been
  # loaded before the nightly job last wrote to it.
  def self.kept(organization) = Organization.where(id: organization.id).pick(:books_check).to_h

  # What the superadmins were last told about these books: each account that
  # disagreed and by how much. The nightly job tells them again only when
  # this changes (BooksReconciliationJob), and keeps it here; a page running
  # the checks during the day leaves it alone, so what it finds is still
  # news that night.
  def self.signature(mismatches) = mismatches.map { |m| [ m.account.to_s, m.difference_cents ] }.sort

  def self.news?(organization, mismatches)
    signature(mismatches) != Array(kept(organization)["alerted"])
  end

  def self.told!(organization, mismatches)
    organization.update_column(:books_check, kept(organization).merge("alerted" => signature(mismatches)))
  end

  # What the checks said when they last ran; run once when they never have.
  def self.last(organization)
    kept = organization.books_check
    return record!(organization) if kept.blank? || kept["at"].blank?

    Array(kept["mismatches"]).map { |m| Mismatch.new(account: m["account"], books_cents: m["books_cents"].to_i, expected_cents: m["expected_cents"].to_i) }
  end

  def self.last_run_at(organization)
    at = organization.books_check&.dig("at")
    at.present? ? Time.zone.parse(at) : nil
  end

  def self.check(organization)
    [ balance_check(organization), owed_check(organization), tax_check(organization), bills_check(organization), contractors_check(organization) ].compact
  end

  # Money you owe is the unpaid part of every open bill (Books V1.3). Money
  # owed to you has no check yet: contract payments don't post at issue.
  def self.bills_check(organization)
    books = ChartOfAccounts.account(organization, :you_owe).natural_balance_cents
    expected = Bill.open.where(organization: organization).sum("amount_cents - paid_cents")
    Mismatch.new(account: "you_owe", books_cents: books, expected_cents: expected) unless books == expected
  end

  # Owed to contractors is every contract payment to them whose date has
  # come and that isn't paid or on a run yet (BooksOutsidePoster).
  def self.contractors_check(organization)
    books = ChartOfAccounts.account(organization, :owed_to_contractors).natural_balance_cents
    pending = ContractPayment.joins(:contract).where(contracts: { organization_id: organization.id })
                             .status_pending.direction_outgoing.where(amount_tbd: false).where("amount > 0")
                             .where("due_date <= ?", Date.current)
    pending = pending.to_a
    on_rail = BooksOutsidePoster.on_the_rail_ids(pending)
    expected = pending.reject { |payment| on_rail.include?(payment.id) }.sum(&:amount_cents)
    Mismatch.new(account: "owed_to_contractors", books_cents: books, expected_cents: expected) unless books == expected
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
    # Plus the tax owed on tickets other sites sold (OutsideTicketTax), less
    # what the organization has marked paid to the government.
    outside = OutsideTicketTax.owed_total_cents(organization)
    # Plus the sales tax a register collected on days that are settled
    # (RegisterSalesTax): it posts with the day, so it counts with the day.
    register = RegisterSalesTax.owed_total_cents(organization)
    paid = SalesTaxRemittance.where(organization_id: organization.id).sum(:amount_cents)
    expected = tickets + products + courses + passes + outside + register - paid
    Mismatch.new(account: "tax_to_remit", books_cents: books, expected_cents: expected) unless books == expected
  end

  private_class_method :balance_check, :owed_check, :tax_check, :bills_check
end

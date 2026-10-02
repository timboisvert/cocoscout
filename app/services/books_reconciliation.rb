# frozen_string_literal: true

# Checks an organization's books against the detailed records they summarize,
# so a posting that was missed (or posted twice) shows up the next morning
# instead of in a tax filing. Each check compares one account with what it
# should equal:
#
#   CocoScout balance — ticket money in the cash ledger (sales, refunds,
#                       disputes and money added from the bank) less what was
#                       withdrawn to the bank. (Payout runs join the books in stage B.)
#   Tax to remit      — the tax_lines on paid ticket orders, less refunds.
#
# Returns the mismatches; none means the books agree.
class BooksReconciliation
  Mismatch = Data.define(:account, :books_cents, :expected_cents) do
    def difference_cents
      books_cents - expected_cents
    end
  end

  def self.check(organization)
    [ balance_check(organization), tax_check(organization) ].compact
  end

  def self.balance_check(organization)
    books = ChartOfAccounts.account(organization, :cocoscout_balance).natural_balance_cents
    cash = OrgCashEntry.where(organization: organization, entry_type: TicketBalance::ENTRY_TYPES + %w[top_up]).sum(:amount_cents)
    withdrawn = organization.balance_withdrawals.where(status: "sent").sum(:amount_cents)
    expected = cash - withdrawn
    Mismatch.new(account: "cocoscout_balance", books_cents: books, expected_cents: expected) unless books == expected
  end

  def self.tax_check(organization)
    books = ChartOfAccounts.account(organization, :tax_to_remit).natural_balance_cents
    expected = TaxLine.where(organization_id: organization.id, taxable_type: "Ticket", remitter: "organization")
                      .joins("JOIN tickets ON tickets.id = tax_lines.taxable_id JOIN ticket_orders ON ticket_orders.id = tickets.ticket_order_id")
                      .where(ticket_orders: { status: TicketOrder::WAS_PAID, money_path: %w[cocoscout cash] })
                      .sum(:tax_cents)
    Mismatch.new(account: "tax_to_remit", books_cents: books, expected_cents: expected) unless books == expected
  end

  private_class_method :balance_check, :tax_check
end

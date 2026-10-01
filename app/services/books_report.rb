# frozen_string_literal: true

# What the read-only Books page shows (Money → Books): every account's
# balance, the entries behind them, and ticket money show by show. Plain
# names throughout; the engine underneath is LedgerPosting.
class BooksReport
  GROUPS = [
    [ "asset", "Money you have" ],
    [ "liability", "Money you owe" ],
    [ "equity", "Owner's equity" ],
    [ "income", "Income" ],
    [ "expense", "Spending" ]
  ].freeze

  # What each kind of entry was, in words.
  KIND_LABELS = {
    "sale" => "Ticket sale",
    "refund" => "Ticket refund",
    "recognition" => "Show happened: ticket income",
    "withdrawal" => "Withdrawal to the bank",
    "dispute" => "Disputed charge"
  }.freeze

  Row = Data.define(:account, :cents)
  ShowRow = Data.define(:show, :waiting_cents, :income_cents, :tax_cents)

  def initialize(organization, basis: :accrual)
    @organization = organization
    @basis = basis.to_s == "cash" ? :cash : :accrual
  end

  attr_reader :basis

  # [[group label, [Row...], total cents], ...] — each balance as a person
  # reads it (positive on the account's normal side).
  def groups
    sums = signed_sums
    accounts = @organization.ledger_accounts.active.order(:code).to_a
    GROUPS.filter_map do |type, label|
      rows = accounts.select { |a| a.account_type == type }.map do |account|
        signed = sums.fetch(account.id, 0)
        Row.new(account: account, cents: LedgerAccount::DEBIT_NORMAL.include?(type) ? signed : -signed)
      end
      next if rows.empty?

      [ label, rows, rows.sum(&:cents) ]
    end
  end

  def profit_cents
    income = groups.find { |label, _, _| label == "Income" }&.last.to_i
    spending = groups.find { |label, _, _| label == "Spending" }&.last.to_i
    income - spending
  end

  # Every line ever posted sums to zero in healthy books.
  def trial_balance_cents
    JournalLine.where(organization_id: @organization.id).sum(:amount_cents)
  end

  def entries(account_id: nil, show_id: nil, kind: nil)
    scope = JournalEntry.where(organization_id: @organization.id)
                        .includes(journal_lines: :ledger_account)
                        .order(entry_date: :desc, id: :desc)
    scope = scope.where(kind: kind) if kind.present?
    line_filter = JournalLine.where(organization_id: @organization.id)
    line_filter = line_filter.where(ledger_account_id: account_id) if account_id.present?
    line_filter = line_filter.where(show_id: show_id) if show_id.present?
    scope = scope.where(id: line_filter.select(:journal_entry_id)) if account_id.present? || show_id.present?
    scope
  end

  # Ticket money by show: still waiting on the show, recognized as income,
  # and the tax collected for it.
  def by_show
    keys = %w[advance_ticket_sales ticket_income tax_to_remit]
    accounts = @organization.ledger_accounts.where(key: keys).index_by(&:key)
    return [] if accounts.empty?

    sums = JournalLine.where(organization_id: @organization.id, ledger_account_id: accounts.values.map(&:id))
                      .where.not(show_id: nil)
                      .group(:show_id, :ledger_account_id).sum(:amount_cents)
    shows = Show.where(id: sums.keys.map(&:first).uniq).includes(:production).index_by(&:id)
    pick = ->(show_id, key) { accounts[key] ? -sums.fetch([ show_id, accounts[key].id ], 0) : 0 }
    shows.values.sort_by(&:date_and_time).reverse.map do |show|
      ShowRow.new(show: show, waiting_cents: pick.call(show.id, "advance_ticket_sales"),
                  income_cents: pick.call(show.id, "ticket_income"), tax_cents: pick.call(show.id, "tax_to_remit"))
    end
  end

  private

  def signed_sums
    lines = JournalLine.where(organization_id: @organization.id).joins(:journal_entry)
    lines = lines.where.not(journal_entries: { cash_date: nil }) if @basis == :cash
    lines.group(:ledger_account_id).sum(:amount_cents)
  end
end

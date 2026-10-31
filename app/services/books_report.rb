# frozen_string_literal: true

require "csv"

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
    "dispute" => "Disputed charge",
    "outside_tickets" => "Tickets sold elsewhere",
    "other_revenue" => "Other revenue",
    "flat_fee" => "Flat fee",
    "expenses" => "Show expenses",
    "production_expense" => "Production expense",
    "contract_payment" => "Contract payment",
    "cocoscout_bill" => "CocoScout bill",
    "recorded" => "Recorded by hand",
    "settlement" => "Day settled"
  }.freeze

  Row = Data.define(:account, :cents)
  ShowRow = Data.define(:show, :waiting_cents, :income_cents, :tax_cents)
  # The Overview (Books' landing page) for a period: money in by kind, money
  # out by category, both by week, and what's left by production.
  Overview = Data.define(:range, :in_cents, :out_cents, :in_rows, :out_rows, :weeks, :productions) do
    def left_cents = in_cents - out_cents
    def empty? = in_rows.empty? && out_rows.empty?
  end
  Week = Data.define(:starts_on, :label, :in_cents, :out_cents)
  ProductionRow = Data.define(:production, :name, :in_cents, :out_cents) do
    def left_cents = in_cents - out_cents
  end

  # The periods the Overview offers. nil = all time.
  PERIODS = {
    "this_month" => -> { Time.current.beginning_of_month..Time.current.end_of_month },
    "last_month" => -> { 1.month.ago.beginning_of_month..1.month.ago.end_of_month },
    "this_quarter" => -> { Time.current.beginning_of_quarter..Time.current.end_of_quarter },
    "this_year" => -> { Time.current.beginning_of_year..Time.current.end_of_year },
    "last_year" => -> { 1.year.ago.beginning_of_year..1.year.ago.end_of_year },
    "all_time" => -> { nil }
  }.freeze
  PERIOD_LABELS = {
    "this_month" => "This month", "last_month" => "Last month", "this_quarter" => "This quarter",
    "this_year" => "This year", "last_year" => "Last year", "all_time" => "All time"
  }.freeze

  def self.period_range(key)
    (PERIODS[key.to_s] || PERIODS["this_month"]).call
  end

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

  # The Overview as a spreadsheet: every income and spending line in the
  # period, with what it was for and when it was earned and moved.
  def to_csv(range:, production_id: nil)
    lines = dated_lines(range).includes(:ledger_account, :production, :show, journal_entry: [])
                              .where(ledger_accounts: { account_type: %w[income expense] })
                              .order("journal_entries.entry_date, journal_entries.id, journal_lines.id")
    lines = lines.where(production_id: production_id) if production_id.present?
    CSV.generate do |csv|
      csv << [ "Earned on", "Moved on", "What", "Description", "Category", "Production", "Show", "In", "Out" ]
      lines.each do |line|
        entry = line.journal_entry
        income = line.ledger_account.account_type == "income"
        cents = income ? -line.amount_cents : line.amount_cents
        csv << [ entry.entry_date, entry.cash_date, KIND_LABELS.fetch(entry.kind, entry.kind.humanize), entry.memo,
                 line.ledger_account.name, line.production&.name, line.show && "#{line.show.date_and_time.strftime('%Y-%m-%d')} #{line.show.display_name}",
                 (income ? format("%.2f", cents / 100.0) : nil), (income ? nil : format("%.2f", cents / 100.0)) ]
      end
    end
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

  # Everything the Overview shows for a period, read from the lines. Dates
  # follow the basis: when earned (entry_date) or when it moved (cash_date).
  # production_id narrows to one production's lines.
  def overview(range:, production_id: nil)
    lines = dated_lines(range)
    lines = lines.where(production_id: production_id) if production_id.present?
    accounts = @organization.ledger_accounts.where(account_type: %w[income expense]).index_by(&:id)
    by_account = lines.where(ledger_account_id: accounts.keys).group(:ledger_account_id).sum(:amount_cents)
    in_rows = []
    out_rows = []
    by_account.each do |account_id, signed|
      account = accounts[account_id]
      next if signed.zero?

      if account.account_type == "income"
        in_rows << Row.new(account: account, cents: -signed)
      else
        out_rows << Row.new(account: account, cents: signed)
      end
    end
    in_rows.sort_by! { |r| -r.cents }
    out_rows.sort_by! { |r| -r.cents }

    Overview.new(range: range, in_cents: in_rows.sum(&:cents), out_cents: out_rows.sum(&:cents),
                 in_rows: in_rows, out_rows: out_rows,
                 weeks: weeks(lines, accounts, range), productions: by_production(lines, accounts))
  end

  # Money in and out by production for the Overview's period; lines with no
  # production (a bill for the organization, a sponsorship) are "Not tied to
  # a production".
  def by_production(lines, accounts)
    sums = lines.where(ledger_account_id: accounts.keys).group(:production_id, :ledger_account_id).sum(:amount_cents)
    buckets = Hash.new { |h, k| h[k] = { in: 0, out: 0 } }
    sums.each do |(production_id, account_id), signed|
      if accounts[account_id].account_type == "income"
        buckets[production_id][:in] -= signed
      else
        buckets[production_id][:out] += signed
      end
    end
    productions = Production.where(id: buckets.keys.compact).index_by(&:id)
    rows = buckets.map do |production_id, b|
      production = productions[production_id]
      next if production_id.present? && production.nil?

      ProductionRow.new(production: production, name: production&.name || "Not tied to a production", in_cents: b[:in], out_cents: b[:out])
    end.compact
    rows.sort_by { |r| [ r.production.nil? ? 1 : 0, -r.in_cents ] }
  end

  private

  # Weeks across the period (Monday to Sunday, clipped to the range); all
  # time means the weeks from the first line to today.
  def weeks(lines, accounts, range)
    date_column = @basis == :cash ? "journal_entries.cash_date" : "journal_entries.entry_date"
    first = range&.begin&.to_date || lines.minimum(date_column)
    last = range&.end&.to_date || Date.current
    return [] if first.nil? || last < first || (last - first) > 400

    sums = lines.where(ledger_account_id: accounts.keys)
                .group(Arel.sql("date_trunc('week', #{date_column})::date"), :ledger_account_id).sum(:amount_cents)
    buckets = Hash.new { |h, k| h[k] = { in: 0, out: 0 } }
    sums.each do |(week, account_id), signed|
      week = week.to_date
      if accounts[account_id].account_type == "income"
        buckets[week][:in] -= signed
      else
        buckets[week][:out] += signed
      end
    end
    week = first.beginning_of_week
    out = []
    while week <= last
      from = [ week, first ].max
      to = [ week.end_of_week, last ].min
      label = from.month == to.month ? "#{from.strftime('%b %-d')}–#{to.day}" : "#{from.strftime('%b %-d')}–#{to.strftime('%b %-d')}"
      out << Week.new(starts_on: week, label: label, in_cents: buckets[week][:in], out_cents: buckets[week][:out])
      week += 7
    end
    out
  end

  def dated_lines(range)
    lines = JournalLine.where(organization_id: @organization.id).joins(:journal_entry)
    if @basis == :cash
      lines = lines.where.not(journal_entries: { cash_date: nil })
      lines = lines.where(journal_entries: { cash_date: range.begin.to_date..range.end.to_date }) if range
    elsif range
      lines = lines.where(journal_entries: { entry_date: range.begin.to_date..range.end.to_date })
    end
    lines
  end

  def signed_sums
    lines = JournalLine.where(organization_id: @organization.id).joins(:journal_entry)
    lines = lines.where.not(journal_entries: { cash_date: nil }) if @basis == :cash
    lines.group(:ledger_account_id).sum(:amount_cents)
  end
end

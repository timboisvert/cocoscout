# frozen_string_literal: true

require "csv"

# The three statements an accountant asks for (Books V1.3, plan E1), in
# plain words, from the same ledger the Overview reads:
#
#   profit_and_loss(range, by_production:)  income and spending for a period
#   balance_sheet(as_of)                     what you have and owe on a day
#   cash_flow(range)                         cash at the start, in, out, at the end
#
# Nonprofit words (Statement of activities, Net assets) when the
# organization says it is one.
class BooksStatements
  Line = Data.define(:label, :cents, :by_production, :emphasis) do
    def initialize(label:, cents:, by_production: {}, emphasis: false) = super
  end
  Section = Data.define(:title, :lines, :total_label, :total_cents, :by_production)
  Statement = Data.define(:kind, :title, :subtitle, :sections, :bottom, :columns, :basis_note)

  CASH_ACCOUNTS = %w[bank door_cash cocoscout_balance].freeze

  def initialize(organization, basis: :accrual)
    @organization = organization
    @basis = basis.to_s == "cash" ? :cash : :accrual
    @report = BooksReport.new(organization, basis: @basis)
  end

  attr_reader :basis

  def nonprofit? = @organization.books_nonprofit

  def words
    nonprofit? ? { pnl: "Statement of activities", profit: "Change in net assets", equity: "Net assets", income: "Support and revenue", spending: "Expenses" }
               : { pnl: "Profit and loss", profit: "Profit", equity: "Owner's equity", income: "Income", spending: "Spending" }
  end

  # Income and spending for a period, by account; optionally a column per
  # production (and one for money not tied to any).
  def profit_and_loss(range, by_production: false)
    lines = @report.dated_lines(range).joins(:ledger_account).where(ledger_accounts: { account_type: %w[income expense] })
    sums = lines.group("ledger_accounts.id").sum(:amount_cents)
    prod_sums = by_production ? lines.group("ledger_accounts.id", :production_id).sum(:amount_cents) : {}
    accounts = @organization.ledger_accounts.active.where(id: sums.keys).order(:code).to_a
    productions = by_production ? production_columns(prod_sums.keys.map(&:last)) : []

    build = lambda do |type|
      rows = accounts.select { |a| a.account_type == type }.filter_map do |a|
        cents = type == "income" ? -sums[a.id].to_i : sums[a.id].to_i
        next if cents.zero?

        per = productions.to_h { |pid, _| [ pid, (type == "income" ? -prod_sums[[ a.id, pid ]].to_i : prod_sums[[ a.id, pid ]].to_i) ] }
        Line.new(label: a.name, cents: cents, by_production: per)
      end
      Section.new(title: (type == "income" ? words[:income] : words[:spending]), lines: rows, total_label: "Total #{(type == 'income' ? words[:income] : words[:spending]).downcase}",
                  total_cents: rows.sum(&:cents), by_production: productions.to_h { |pid, _| [ pid, rows.sum { |r| r.by_production[pid].to_i } ] })
    end
    income = build.call("income")
    spending = build.call("expense")
    Statement.new(kind: "pnl", title: words[:pnl], subtitle: period_label(range), sections: [ income, spending ],
                  bottom: Line.new(label: words[:profit], cents: income.total_cents - spending.total_cents,
                                   by_production: productions.to_h { |pid, _| [ pid, income.by_production[pid].to_i - spending.by_production[pid].to_i ] }, emphasis: true),
                  columns: productions, basis_note: basis_note)
  end

  # What you have and what you owe on a day. Equity closes itself: every
  # dollar of income less spending to that day sits in retained earnings,
  # so the two sides always agree.
  def balance_sheet(as_of)
    lines = JournalLine.where(organization_id: @organization.id).joins(:journal_entry, :ledger_account)
    date_column = @basis == :cash ? "journal_entries.cash_date" : "journal_entries.entry_date"
    lines = lines.where.not(journal_entries: { cash_date: nil }) if @basis == :cash
    lines = lines.where("#{date_column} <= ?", as_of)
    sums = lines.group("ledger_accounts.id").sum(:amount_cents)
    accounts = @organization.ledger_accounts.active.where(id: sums.keys).order(:code).to_a

    section = lambda do |type, title, total_label|
      rows = accounts.select { |a| a.account_type == type }.filter_map do |a|
        cents = LedgerAccount::DEBIT_NORMAL.include?(type) ? sums[a.id].to_i : -sums[a.id].to_i
        cents.zero? ? nil : Line.new(label: a.name, cents: cents)
      end
      Section.new(title: title, lines: rows, total_label: total_label, total_cents: rows.sum(&:cents), by_production: {})
    end
    assets = section.call("asset", "What you have", "Total of what you have")
    liabilities = section.call("liability", "What you owe", "Total of what you owe")
    equity = section.call("equity", words[:equity], "Total #{words[:equity].downcase}")
    earned = accounts.select { |a| a.account_type.in?(%w[income expense]) }.sum { |a| -sums[a.id].to_i }
    equity_lines = equity.lines + [ Line.new(label: (nonprofit? ? "Net assets from activities to date" : "Earnings kept in the organization to date"), cents: earned) ]
    equity = Section.new(title: equity.title, lines: equity_lines, total_label: equity.total_label, total_cents: equity_lines.sum(&:cents), by_production: {})
    Statement.new(kind: "balance", title: (nonprofit? ? "Statement of financial position" : "Balance sheet"), subtitle: "As of #{as_of.strftime('%B %-d, %Y')}",
                  sections: [ assets, liabilities, equity ],
                  bottom: Line.new(label: "What you owe plus #{words[:equity].downcase}", cents: liabilities.total_cents + equity.total_cents, emphasis: true),
                  columns: [], basis_note: basis_note)
  end

  # Cash at the start of the period, what came in and went out of the cash
  # accounts, and cash at the end. Always by when money moved.
  def cash_flow(range)
    cash_ids = @organization.ledger_accounts.where(key: CASH_ACCOUNTS).pluck(:id)
    base = JournalLine.where(organization_id: @organization.id, ledger_account_id: cash_ids).joins(:journal_entry).where.not(journal_entries: { cash_date: nil })
    opening = base.where("journal_entries.cash_date < ?", range.begin.to_date).sum(:amount_cents)
    in_period = base.where(journal_entries: { cash_date: range.begin.to_date..range.end.to_date })
    by_kind = in_period.group("journal_entries.kind").sum(:amount_cents)
    ins = by_kind.select { |_, c| c.positive? }.map { |k, c| Line.new(label: BooksReport::KIND_LABELS.fetch(k, k.humanize), cents: c) }.sort_by { |l| -l.cents }
    outs = by_kind.select { |_, c| c.negative? }.map { |k, c| Line.new(label: BooksReport::KIND_LABELS.fetch(k, k.humanize), cents: -c) }.sort_by { |l| -l.cents }
    closing_by_account = base.where("journal_entries.cash_date <= ?", range.end.to_date).group(:ledger_account_id).sum(:amount_cents)
    accounts = @organization.ledger_accounts.where(id: cash_ids).order(:code)
    where = accounts.map { |a| Line.new(label: a.name, cents: closing_by_account[a.id].to_i) }
    sections = [
      Section.new(title: "Cash at the start", lines: [ Line.new(label: "Bank, door cash and CocoScout balance together", cents: opening) ], total_label: "Cash at the start", total_cents: opening, by_production: {}),
      Section.new(title: "Came in", lines: ins, total_label: "Total in", total_cents: ins.sum(&:cents), by_production: {}),
      Section.new(title: "Went out", lines: outs, total_label: "Total out", total_cents: outs.sum(&:cents), by_production: {}),
      Section.new(title: "Cash at the end, by where it sits", lines: where, total_label: "Cash at the end", total_cents: where.sum(&:cents), by_production: {})
    ]
    Statement.new(kind: "cash", title: "Cash flow", subtitle: period_label(range), sections: sections,
                  bottom: Line.new(label: "Change in cash", cents: ins.sum(&:cents) - outs.sum(&:cents), emphasis: true), columns: [], basis_note: "Counted when the money moved")
  end

  def to_csv(statement)
    CSV.generate do |csv|
      csv << [ statement.title, statement.subtitle, statement.basis_note ]
      csv << []
      header = [ "", "Total" ] + statement.columns.map(&:last)
      csv << header if statement.columns.any?
      statement.sections.each do |section|
        csv << [ section.title ]
        section.lines.each { |l| csv << [ l.label, dollars(l.cents) ] + statement.columns.map { |pid, _| dollars(l.by_production[pid].to_i) } }
        csv << [ section.total_label, dollars(section.total_cents) ] + statement.columns.map { |pid, _| dollars(section.by_production[pid].to_i) }
        csv << []
      end
      csv << [ statement.bottom.label, dollars(statement.bottom.cents) ] + statement.columns.map { |pid, _| dollars(statement.bottom.by_production[pid].to_i) }
    end
  end

  # Every line ever posted, for an accountant's own tools.
  def ledger_csv
    lines = JournalLine.where(organization_id: @organization.id).includes(:ledger_account, :production, :show, :journal_entry)
                       .joins(:journal_entry).order("journal_entries.entry_date, journal_entries.id, journal_lines.id")
    CSV.generate do |csv|
      csv << [ "Entry", "Earned on", "Moved on", "What", "Memo", "Account code", "Account", "Debit", "Credit", "Production", "Show", "Payee", "Line memo", "Source", "Reverses entry" ]
      lines.find_each(batch_size: 2000) do |line|
        e = line.journal_entry
        csv << [ e.id, e.entry_date, e.cash_date, BooksReport::KIND_LABELS.fetch(e.kind, e.kind.humanize), e.memo, line.ledger_account.code, line.ledger_account.name,
                 (line.amount_cents.positive? ? dollars(line.amount_cents) : nil), (line.amount_cents.negative? ? dollars(-line.amount_cents) : nil),
                 line.production&.name, line.show && "#{line.show.date_and_time.strftime('%Y-%m-%d')} #{line.show.display_name}",
                 line.payee_type && "#{line.payee_type} #{line.payee_id}", line.memo, e.source_type && "#{e.source_type} #{e.source_id}", e.reversal_of_id ]
      end
    end
  end

  private

  def production_columns(ids)
    names = Production.where(id: ids.compact).pluck(:id, :name).to_h
    cols = ids.compact.uniq.sort_by { |id| names[id].to_s }.map { |id| [ id, names[id] ] }
    cols << [ nil, "Not tied to a production" ] if ids.include?(nil)
    cols
  end

  def period_label(range)
    from, to = range.begin.to_date, range.end.to_date
    if from == from.beginning_of_month && to == from.end_of_month then from.strftime("%B %Y")
    elsif from == from.beginning_of_year && to == from.end_of_year then from.year.to_s
    else "#{from.strftime('%b %-d, %Y')} to #{to.strftime('%b %-d, %Y')}"
    end
  end

  def basis_note = @basis == :cash ? "Counted when the money moved" : "Counted when it was earned"
  def dollars(cents) = format("%.2f", cents / 100.0)
end

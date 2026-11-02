# frozen_string_literal: true

# What the Bank page knows besides its rows (plan D3): the statements in,
# the balances to compare, and the counts. Built once for the page and
# again for the Turbo Stream that answers an action on a line, so the tiles
# and the counts move with the row and the page never reloads.
class BankStatementSummary
  attr_reader :organization, :imports, :last, :statement, :open_count, :open_total_cents, :suggested_count, :months,
              :books_bank_cents, :books_bank_on_closing_cents

  def initialize(organization)
    @organization = organization
    @imports = organization.bank_statement_imports.order(created_at: :desc).limit(12).to_a
    @last = @imports.first
    @statement = @imports.select(&:closing_on).max_by(&:closing_on)
    open = organization.bank_statement_lines.to_deal_with
    @open_count = open.count
    @open_total_cents = open.sum(:amount_cents)
    @suggested_count = organization.bank_statement_lines.where(state: "suggested").count
    @months = open.unscope(:order).distinct.pluck(Arel.sql(%(date_trunc('month', "on")::date))).sort.reverse
    bank = ChartOfAccounts.account(organization, :bank)
    @books_bank_cents = bank.natural_balance_cents
    @books_bank_on_closing_cents = @statement ? bank.natural_balance_cents(basis: :cash, as_of: @statement.closing_on) : nil
  end

  def matching? = @imports.any?(&:matching?)
  def applying_rules? = BankRules.applying?(organization)
  def failed = @imports.find(&:failed?)
  def difference_cents = statement&.closing_balance_cents && books_bank_on_closing_cents ? statement.closing_balance_cents - books_bank_on_closing_cents : nil

  # For each line that looks like something on the books: the entries it
  # looks like, in words, loaded in one go. { line id => [ { on:, memo:, kind:, amount_cents: } ] }
  def self.candidates_for(organization, lines)
    ids = lines.flat_map(&:all_journal_line_ids).uniq
    return {} if ids.empty?

    journal_lines = JournalLine.where(id: ids, organization: organization).includes(:journal_entry).index_by(&:id)
    lines.each_with_object({}) do |line, out|
      found = line.all_journal_line_ids.filter_map { |id| journal_lines[id] }
      out[line.id] = found.map { |jl| describe(jl) } if found.any?
    end
  end

  # What was recorded last time for the same payee: the category and the
  # name, offered as the Record it defaults. { description key => { category_key:, counterparty:, label: } }
  def self.hints_for(organization, lines)
    keys = lines.select(&:open?).filter_map(&:description_key).uniq
    return {} if keys.empty?

    organization.bank_statement_lines.where(state: "recorded", description_key: keys).where.not(money_record_id: nil)
                .order(updated_at: :desc).includes(:money_record).each_with_object({}) do |line, out|
      record = line.money_record
      next if record.nil? || out.key?(line.description_key)

      out[line.description_key] = { category_key: record.category_key, counterparty: record.counterparty, label: [ record.category_label, record.counterparty ].compact_blank.join(", ") }
    end
  end

  # A line on the books, in words: what it is, from which entry.
  def self.describe(journal_line)
    entry = journal_line.journal_entry
    kind = BooksReport::KIND_LABELS.fetch(entry.kind, entry.kind.humanize)
    { on: entry.cash_date || entry.entry_date, memo: entry.memo.presence || kind, kind: kind, amount_cents: journal_line.amount_cents }
  end
end

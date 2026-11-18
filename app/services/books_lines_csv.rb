# frozen_string_literal: true

# Walks an organization's journal lines in date order (earned date, entry,
# line), a batch at a time, for the spreadsheets Books hands out. Each batch
# is one query that picks up after the last line of the one before, read as
# plain columns, so a ledger of any length costs the same memory as one
# batch (Tim, 2026-11-09: the whole ledger was built in one go, in the page
# request, and came out in the order the lines were written).
class BooksLinesCsv
  BATCH = 2_000
  ORDER = "journal_entries.entry_date, journal_entries.id, journal_lines.id"
  COLUMNS = %w[
    journal_entries.id journal_entries.entry_date journal_entries.cash_date journal_entries.kind journal_entries.memo
    journal_entries.source_type journal_entries.source_id journal_entries.reversal_of_id
    journal_lines.id journal_lines.ledger_account_id journal_lines.amount_cents journal_lines.production_id journal_lines.show_id
    journal_lines.payee_type journal_lines.payee_id journal_lines.memo
  ].freeze
  Line = Struct.new(:entry_id, :entry_date, :cash_date, :kind, :entry_memo, :source_type, :source_id, :reversal_of_id,
                    :id, :ledger_account_id, :amount_cents, :production_id, :show_id, :payee_type, :payee_id, :memo)

  def initialize(organization)
    @organization = organization
    @shows = {}
  end

  # scope: JournalLine joined to its journal_entry (and whatever else it filters on).
  def each(scope)
    after = nil
    loop do
      page = scope.reorder(Arel.sql(ORDER)).limit(BATCH)
      page = page.where("(journal_entries.entry_date, journal_entries.id, journal_lines.id) > (?, ?, ?)", *after) if after
      lines = page.pluck(*COLUMNS.map { |column| Arel.sql(column) }).map { |values| Line.new(*values) }
      break if lines.empty?

      remember_shows(lines)
      lines.each { |line| yield line }
      after = [ lines.last.entry_date, lines.last.entry_id, lines.last.id ]
      break if lines.size < BATCH
    end
  end

  # [code, name, account_type]
  def account(id)
    @accounts ||= @organization.ledger_accounts.pluck(:id, :code, :name, :account_type).to_h { |account_id, *rest| [ account_id, rest ] }
    @accounts[id] || []
  end

  def production_name(id)
    @productions ||= @organization.productions.pluck(:id, :name).to_h
    @productions[id]
  end

  # "2026-10-31 Holiday Revue", or nil.
  def show_label(id) = @shows[id]

  def kind_label(kind) = BooksReport::KIND_LABELS.fetch(kind, kind.to_s.humanize)

  private

  def remember_shows(lines)
    missing = lines.filter_map(&:show_id).uniq - @shows.keys
    return if missing.empty?

    Show.where(id: missing).includes(:production).each do |show|
      @shows[show.id] = "#{show.date_and_time.strftime('%Y-%m-%d')} #{show.display_name}"
    end
  end
end

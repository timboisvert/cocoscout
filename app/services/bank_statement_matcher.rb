# frozen_string_literal: true

# Matches a statement's lines to what the books already say about the bank
# (plan D3): the same amount on the same day is a match; the same amount
# within a few days is a suggestion to confirm. Each line on the books
# matches one statement line at most.
class BankStatementMatcher
  WINDOW = 5

  def self.run!(organization, lines = organization.bank_statement_lines.where(state: "open"))
    new(organization).run!(lines)
  end

  def initialize(organization)
    @organization = organization
    @bank = ChartOfAccounts.account(organization, :bank)
  end

  def run!(lines)
    lines = lines.to_a
    return if lines.empty?

    taken = @organization.bank_statement_lines.where.not(journal_line_id: nil).pluck(:journal_line_id).to_set
    lines.each do |line|
      exact, near = candidates(line).partition { |c| c[:on] == line.on }
      exact.reject! { |c| taken.include?(c[:id]) }
      near.reject! { |c| taken.include?(c[:id]) }
      if exact.size == 1
        line.update!(state: "matched", journal_line_id: exact.first[:id])
        taken << exact.first[:id]
      elsif (exact + near).size >= 1
        pick = (exact + near).min_by { |c| (c[:on] - line.on).abs }
        line.update!(state: "suggested", journal_line_id: pick[:id])
        taken << pick[:id]
      end
    end
  end

  # Bank-account lines of live entries with this amount, dated within the window.
  def candidates(line)
    JournalLine.joins(:journal_entry).where(organization: @organization, ledger_account: @bank, amount_cents: line.amount_cents)
               .merge(JournalEntry.live)
               .where("COALESCE(journal_entries.cash_date, journal_entries.entry_date) BETWEEN ? AND ?", line.on - WINDOW, line.on + WINDOW)
               .pluck(:id, Arel.sql("COALESCE(journal_entries.cash_date, journal_entries.entry_date)"))
               .map { |id, on| { id: id, on: on } }
  end
end

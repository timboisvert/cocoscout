# frozen_string_literal: true

# Matches a statement's lines to what the books already say about the bank
# (plan D3). Runs in BankStatementMatchJob, so it can take its time.
#
# For each statement line, the candidates are the bank-account lines of live
# entries with the same amount within two weeks. Each is scored: closer in
# time is better, a word the bank's description shares with the entry (the
# payee, a show) is better, and a description that names the kind of entry
# (STRIPE for a withdrawal, HOTTIX for tickets sold elsewhere, COCOSCOUT for
# our bill) is better. The best candidate is a match when it is sure: the
# same day and the only one, or named and clearly ahead. Otherwise it is a
# suggestion to confirm.
#
# A line with no candidate of its own may be a group: a ticket seller or a
# processor pays several shows in one deposit. The entries of the same sign
# in the three weeks before it (and three days after) are searched for the
# one set that adds up to it; found, it is a suggestion carrying all of
# them. Each line on the books goes to one statement line at most.
class BankStatementMatcher
  WINDOW = 14
  GROUP_BEFORE = 21
  GROUP_AFTER = 3
  GROUP_MAX = 6
  GROUP_POOL = 30
  SURE = 110
  CLEARLY = 20

  # Words that say nothing about who was paid.
  STOP = %w[the and for inc llc ltd corp payment online card purchase debit credit transfer deposit withdrawal check
            orig name entry descr sec ccd ppd web tel ind trace eed trn pos ach zelle des id co from to via with
            show shows ticket tickets night event].to_set.freeze
  # What a bank description says about the kind of entry it is.
  KIND_HINTS = [
    [ /COCO\s*SCOUT/i, %w[cocoscout_bill cash] ],
    [ /STRIPE/i, %w[withdrawal cash] ],
    [ /HOT\s*TIX|CHGTHEATRES|CHICAGO THEATRE|EVENTBRITE|TICKET\s*TAILOR|GOLDSTAR|TODAYTIX|SQUARE/i, %w[outside_tickets] ]
  ].freeze

  Result = Struct.new(:matched, :suggested, keyword_init: true)
  Candidate = Struct.new(:id, :amount_cents, :on, :text, :kind, keyword_init: true)

  def self.run!(organization, lines = organization.bank_statement_lines.where(state: "open"))
    new(organization).run!(lines)
  end

  def initialize(organization)
    @organization = organization
    @bank = ChartOfAccounts.account(organization, :bank)
  end

  def run!(lines)
    lines = lines.to_a.sort_by { |l| [ l.on, l.id ] }
    result = Result.new(matched: 0, suggested: 0)
    return result if lines.empty?

    @taken = taken_ids
    @by_amount = load_candidates(lines.first.on - GROUP_BEFORE, lines.last.on + WINDOW).group_by(&:amount_cents)
    lines.each do |line|
      if (pick = single(line))
        state, candidate = pick
        line.public_send(state == "matched" ? :match! : :suggest!, JournalLine.where(id: candidate.id).to_a)
        @taken << candidate.id
        state == "matched" ? result.matched += 1 : result.suggested += 1
      elsif (group = group(line))
        line.suggest!(JournalLine.where(id: group.map(&:id)).to_a)
        @taken.merge(group.map(&:id))
        result.suggested += 1
      end
    end
    result
  end

  private

  # Lines on the books already matched or suggested to another statement line.
  def taken_ids
    rows = @organization.bank_statement_lines.where.not(state: "open").pluck(:journal_line_id, :journal_line_ids)
    rows.flat_map { |id, ids| ids.presence || [ id ] }.compact.to_set
  end

  def load_candidates(from, to)
    rows = JournalLine.joins(:journal_entry).where(organization: @organization, ledger_account: @bank).merge(JournalEntry.live)
                      .where("COALESCE(journal_entries.cash_date, journal_entries.entry_date) BETWEEN ? AND ?", from, to)
                      .pluck(:id, :amount_cents, Arel.sql("COALESCE(journal_entries.cash_date, journal_entries.entry_date)"),
                             Arel.sql("journal_entries.memo"), Arel.sql("journal_entries.kind"), Arel.sql("journal_entries.source_type"), Arel.sql("journal_entries.source_id"))
    # A money record's counterparty is the name the bank is likeliest to use.
    record_ids = rows.filter_map { |r| r[6] if r[5] == "MoneyRecord" }
    names = record_ids.any? ? MoneyRecord.where(id: record_ids).pluck(:id, :counterparty).to_h : {}
    rows.map do |id, amount, on, memo, kind, source_type, source_id|
      text = [ memo, (names[source_id] if source_type == "MoneyRecord") ].compact_blank.join(" ")
      Candidate.new(id: id, amount_cents: amount, on: on, text: text, kind: kind)
    end
  end

  # [state, candidate] for the best same-amount line within the window, or nil.
  def single(line)
    pool = (@by_amount[line.amount_cents] || []).reject { |c| @taken.include?(c.id) || (c.on - line.on).abs > WINDOW }
    return nil if pool.empty?

    scored = pool.map { |c| [ score(line, c), c ] }.sort_by { |s, c| [ -s, (c.on - line.on).abs, c.id ] }
    best_score, best = scored.first
    runner_up = scored[1]&.first
    days = (best.on - line.on).abs
    named = named?(line, best)
    sure = (days.zero? && pool.size == 1) ||
           (named && days <= 3 && pool.size == 1) ||
           (named && best_score >= SURE && (runner_up.nil? || best_score - runner_up >= CLEARLY))
    [ sure ? "matched" : "suggested", best ]
  end

  def score(line, candidate)
    100 - (candidate.on - line.on).abs * 5 + shared_words(line, candidate).size * 15 + (kind_hint?(line, candidate) ? 25 : 0)
  end

  def named?(line, candidate) = shared_words(line, candidate).any? || kind_hint?(line, candidate)

  def shared_words(line, candidate)
    words(line.description) & words(candidate.text)
  end

  def words(text)
    text.to_s.downcase.scan(/[a-z]{3,}/).reject { |w| STOP.include?(w) }.to_set
  end

  def kind_hint?(line, candidate)
    KIND_HINTS.any? { |pattern, kinds| line.description.to_s.match?(pattern) && kinds.include?(candidate.kind) }
  end

  # The one set of same-sign lines in the group window that adds up to this
  # line, or nil when there is none or more than one. Lines of the kind the
  # description names are tried first, then everything.
  def group(line)
    pool = @by_amount.values.flatten.select do |c|
      !@taken.include?(c.id) && c.amount_cents.positive? == line.amount_cents.positive? &&
        c.amount_cents.abs < line.amount_cents.abs && c.on.between?(line.on - GROUP_BEFORE, line.on + GROUP_AFTER)
    end
    return nil if pool.size < 2

    hinted = pool.select { |c| kind_hint?(line, c) }
    [ hinted, pool ].uniq.each do |set|
      next if set.size < 2

      set = set.sort_by { |c| (c.on - line.on).abs }.first(GROUP_POOL).sort_by { |c| -c.amount_cents.abs }
      solutions = subsets(set, line.amount_cents.abs)
      return solutions.first if solutions.size == 1
    end
    nil
  end

  # Up to two subsets of at most GROUP_MAX lines whose absolute amounts sum
  # to target; two is enough to know it's ambiguous. set is sorted largest
  # first so the remaining-sum pruning bites early.
  def subsets(set, target)
    found = []
    amounts = set.map { |c| c.amount_cents.abs }
    suffix = Array.new(amounts.size + 1, 0)
    (amounts.size - 1).downto(0) { |i| suffix[i] = suffix[i + 1] + amounts[i] }
    search = lambda do |start, remaining, chosen|
      return if found.size >= 2
      if remaining.zero?
        found << chosen.dup if chosen.size >= 2
        return
      end
      return if chosen.size >= GROUP_MAX || start >= amounts.size || suffix[start] < remaining

      (start...amounts.size).each do |i|
        next if amounts[i] > remaining
        break if suffix[i] < remaining

        chosen << set[i]
        search.call(i + 1, remaining - amounts[i], chosen)
        chosen.pop
        return if found.size >= 2
      end
    end
    search.call(0, target, [])
    found
  end
end

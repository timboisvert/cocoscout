# frozen_string_literal: true

# Balances that don't cost more every year (Books V1.3). An account's
# balance used to be the sum of every line ever posted to it; here it is
# the finished months, kept one row per account per month, plus the lines
# dated since.
#
#   BooksBalances.sums(org)                                  # { account id => signed cents }, all time
#   BooksBalances.sums(org, to: Date.new(2026, 12, 31))      # as of a day
#   BooksBalances.sums(org, from: a, to: b, basis: :cash)    # a period, by when money moved
#   BooksBalances.roll!(org)                                 # nightly: keep the months that finished
#
# How the kept months stay right:
#   - books_rollups.rolled_through is the last day they cover. A month
#     after it is never read from the rows, whatever rows exist.
#   - roll! stops a full month short of today, so the month being worked in
#     and the one before it are always added up from the lines.
#   - LedgerPosting tells posted! about every entry it writes. One dated in
#     a month that could already be kept moves rolled_through back to
#     before it, and the next roll! rebuilds from there. Until then those
#     months are added up from the lines, which is what happened before any
#     of this existed.
#   - A posting and a roll can't pass each other unseen: the roll holds a
#     lock on the organization's books while it adds up, and a posting into
#     an earlier month waits for it (and the roll for the posting).
class BooksBalances
  LOCK = 7_402_613

  def self.sums(organization, basis: :accrual, from: nil, to: nil, account_ids: nil)
    organization_id = organization.is_a?(Organization) ? organization.id : organization
    cash = basis.to_s == "cash"
    from = from&.to_date
    to = to&.to_date
    return {} if from && to && from > to

    rolled = rolled_through(organization_id)
    # The whole months inside the span that are kept: first_month..kept_to.
    first_month = from && (from.day == 1 ? from : from.next_month.beginning_of_month)
    kept_to = rolled && (to.nil? || to >= rolled ? rolled : (to == to.end_of_month ? to : to.beginning_of_month - 1))
    use_kept = kept_to && (first_month.nil? || first_month <= kept_to)

    out = Hash.new(0)
    if use_kept
      rows = LedgerMonthBalance.where(organization_id: organization_id).where(month: ..kept_to.beginning_of_month)
      rows = rows.where(month: first_month..) if first_month
      rows = rows.where(ledger_account_id: account_ids) if account_ids
      rows.group(:ledger_account_id).sum(cash ? :cash_cents : :accrual_cents).each { |id, cents| out[id] += cents.to_i }
      live(organization_id, cash, from, first_month - 1, account_ids).each { |id, cents| out[id] += cents } if first_month && from < first_month
      live(organization_id, cash, kept_to + 1, to, account_ids).each { |id, cents| out[id] += cents } if to.nil? || to > kept_to
    else
      live(organization_id, cash, from, to, account_ids).each { |id, cents| out[id] += cents }
    end
    out.default = nil
    out
  end

  # The lines themselves, added up for a span of days (either end open).
  def self.live(organization_id, cash, from, to, account_ids = nil)
    lines = JournalLine.where(organization_id: organization_id).joins(:journal_entry)
    lines = lines.where(ledger_account_id: account_ids) if account_ids
    column = cash ? "journal_entries.cash_date" : "journal_entries.entry_date"
    lines = lines.where.not(journal_entries: { cash_date: nil }) if cash
    lines = lines.where("#{column} >= ?", from) if from
    lines = lines.where("#{column} <= ?", to) if to
    lines.group(:ledger_account_id).sum(:amount_cents).transform_values(&:to_i)
  end

  # The last day a roll may cover today: the end of the month before last.
  def self.rollable_through(today = Date.current) = today.beginning_of_month.prev_month - 1

  # An entry was written with this date (the earlier of when it was earned
  # and when its money moved). Called inside the posting's transaction.
  def self.posted!(organization, date, today: Date.current)
    return if date.nil? || date >= today.beginning_of_month

    # Shared: postings don't wait for each other, only for a roll.
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock_shared(#{LOCK}, #{organization.id.to_i})")
    back_to = date.beginning_of_month - 1
    BooksRollup.where(organization_id: organization.id).where("rolled_through >= ?", date).update_all(rolled_through: back_to, updated_at: Time.current)
  end

  def self.rolled_through(organization_id) = BooksRollup.where(organization_id: organization_id).pick(:rolled_through)

  # Keep every finished month not kept yet. Answers how many months it wrote.
  def self.roll!(organization, today: Date.current)
    target = rollable_through(today)
    Organization.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK}, #{organization.id.to_i})")
      rolled = rolled_through(organization.id)
      start = rolled ? rolled + 1 : first_month(organization)
      next 0 if start.nil? || start > target

      LedgerMonthBalance.where(organization_id: organization.id).where(month: start..).delete_all
      moved = Hash.new { |h, k| h[k] = [ 0, 0 ] }
      monthly(organization, "entry_date", start, target).each { |(account, month), cents| moved[[ account, month.to_date ]][0] = cents.to_i }
      monthly(organization, "cash_date", start, target).each { |(account, month), cents| moved[[ account, month.to_date ]][1] = cents.to_i }
      now = Time.current
      rows = moved.map do |(account, month), (accrual, cash)|
        { organization_id: organization.id, ledger_account_id: account, month: month, accrual_cents: accrual, cash_cents: cash, created_at: now, updated_at: now }
      end
      rows.each_slice(1_000) { |slice| LedgerMonthBalance.insert_all!(slice) }
      BooksRollup.upsert({ organization_id: organization.id, rolled_through: target, created_at: now, updated_at: now }, unique_by: :organization_id)
      ((target.year * 12 + target.month) - (start.year * 12 + start.month)) + 1
    end
  end

  # Forget the kept months: everything is added up from the lines until the
  # next roll (after history is rewritten wholesale, or when verify! finds
  # them wrong).
  def self.reset!(organization)
    Organization.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK}, #{organization.id.to_i})")
      LedgerMonthBalance.where(organization_id: organization.id).delete_all
      BooksRollup.where(organization_id: organization.id).delete_all
    end
  end

  # The kept months against the lines they stand for, on both bases: the
  # account ids that disagree. Nightly, before the roll; a difference
  # resets the kept months so nothing wrong is ever shown twice.
  def self.verify!(organization)
    rolled = rolled_through(organization.id)
    return [] unless rolled

    off = %i[accrual cash].flat_map do |basis|
      kept = LedgerMonthBalance.where(organization_id: organization.id).where(month: ..rolled.beginning_of_month)
                               .group(:ledger_account_id).sum(basis == :cash ? :cash_cents : :accrual_cents).transform_values(&:to_i).reject { |_, c| c.zero? }
      lines = live(organization.id, basis == :cash, nil, rolled).reject { |_, c| c.zero? }
      (kept.keys | lines.keys).reject { |id| kept[id].to_i == lines[id].to_i }
    end.uniq
    reset!(organization) if off.any?
    off
  end

  def self.first_month(organization)
    earned = JournalEntry.where(organization_id: organization.id).minimum(:entry_date)
    moved = JournalEntry.where(organization_id: organization.id).minimum(:cash_date)
    [ earned, moved ].compact.min&.beginning_of_month
  end

  def self.monthly(organization, column, start, target)
    JournalLine.where(organization_id: organization.id).joins(:journal_entry)
               .where("journal_entries.#{column} BETWEEN ? AND ?", start, target)
               .group(:ledger_account_id, Arel.sql("date_trunc('month', journal_entries.#{column})::date"))
               .sum(:amount_cents)
  end
end

# frozen_string_literal: true

# The only way money reaches an organization's books.
#
#   LedgerPosting.post!(
#     organization: org, source: order, kind: "sale",
#     entry_date: show_date, cash_date: Date.current, memo: "Ticket sale K7F2Q",
#     lines: [
#       { account: :cocoscout_balance, amount_cents: 1_862 },
#       { account: :ticketing_fees, amount_cents: 138 },
#       { account: :advance_ticket_sales, amount_cents: -2_000, show: show, production: production }
#     ]
#   )
#
# Lines are debit +, credit −, and must sum to zero. Zero-amount lines are
# dropped. Each line may carry the dimensions money is sliced by: show,
# production, payee and fund_id.
#
# Idempotent per (source, kind), like PayoutLedgerEntry.post!: posting the same
# thing again is a no-op; posting something different restates it — the old
# entry is reversed and the new one stands — so history is never edited.
class LedgerPosting
  class Unbalanced < StandardError; end

  def self.post!(organization:, source:, kind:, entry_date:, lines:, cash_date: nil, memo: nil)
    normalized = normalize(organization, lines)
    total = normalized.sum { |line| line[:amount_cents] }
    raise Unbalanced, "#{kind} lines sum to #{total}¢, not zero" unless total.zero?

    JournalEntry.transaction do
      existing = live_entry(source, kind)

      if normalized.empty?
        # Nothing left to say (a free order, a fully refunded one): withdraw
        # whatever stood before.
        reverse!(existing) if existing
        nil
      elsif existing && same?(existing, normalized, entry_date, cash_date)
        existing
      else
        reverse!(existing) if existing
        write!(organization, source: source_attributes(source), kind: kind, entry_date: entry_date,
                             cash_date: cash_date, memo: memo, lines: normalized)
      end
    end
  end

  # Withdraw what a source posted under a kind. Safe no-op if nothing stands.
  def self.unpost!(source:, kind:)
    entry = live_entry(source, kind)
    entry && reverse!(entry)
  end

  # Post the exact opposite of an entry, dated today (a correction lands when
  # it's made, so a closed month never shifts), and mark the original reversed.
  def self.reverse!(entry, memo: nil)
    JournalEntry.transaction do
      entry.update!(reversed_at: Time.current)
      opposite = entry.journal_lines.map do |line|
        line.attributes.symbolize_keys
            .slice(:ledger_account_id, :production_id, :show_id, :payee_type, :payee_id, :fund_id, :memo)
            .merge(amount_cents: -line.amount_cents)
      end
      write!(entry.organization, source: { source_type: entry.source_type, source_id: entry.source_id }, kind: entry.kind,
                                 entry_date: Date.current, cash_date: entry.cash_date && Date.current,
                                 memo: memo || "Reverses: #{entry.memo || entry.kind}",
                                 lines: opposite, reversal_of: entry)
    end
  end

  # Every account's signed balance, keyed by account key (or code for accounts
  # a theater added). A healthy set of books always totals zero.
  def self.trial_balance(organization)
    JournalLine.where(organization_id: organization.id)
               .joins(:ledger_account)
               .group("COALESCE(ledger_accounts.key, ledger_accounts.code)")
               .sum(:amount_cents)
  end

  def self.live_entry(source, kind)
    return nil unless source

    JournalEntry.live.find_by(source_type: source.class.polymorphic_name, source_id: source.id, kind: kind)
  end

  def self.write!(organization, source:, kind:, entry_date:, cash_date:, memo:, lines:, reversal_of: nil)
    entry = JournalEntry.create!(**source, organization: organization, kind: kind,
                                 entry_date: entry_date, cash_date: cash_date, memo: memo,
                                 posted_at: Time.current, reversal_of: reversal_of)
    now = Time.current
    JournalLine.insert_all!(lines.map { |line|
      line.merge(journal_entry_id: entry.id, organization_id: organization.id, created_at: now, updated_at: now)
    })
    raise Unbalanced, "entry #{entry.id} doesn't balance" unless entry.reload.balanced?

    entry
  end

  def self.source_attributes(source)
    source ? { source_type: source.class.polymorphic_name, source_id: source.id } : {}
  end

  def self.normalize(organization, lines)
    lines.filter_map do |line|
      cents = Integer(line.fetch(:amount_cents))
      next if cents.zero?

      account = line[:account].is_a?(LedgerAccount) ? line[:account] : ChartOfAccounts.account(organization, line[:account])
      raise ArgumentError, "account belongs to another organization" unless account.organization_id == organization.id

      payee = line[:payee]
      {
        ledger_account_id: account.id,
        amount_cents: cents,
        production_id: line[:production]&.id || line[:production_id],
        show_id: line[:show]&.id || line[:show_id],
        payee_type: payee&.class&.polymorphic_name,
        payee_id: payee&.id,
        fund_id: line[:fund_id],
        memo: line[:memo]
      }
    end
  end

  def self.same?(entry, normalized, entry_date, cash_date)
    return false unless entry.entry_date == entry_date.to_date && entry.cash_date == cash_date&.to_date

    signature = ->(rows) { rows.map { |r| r.values_at(:ledger_account_id, :amount_cents, :production_id, :show_id, :payee_type, :payee_id, :fund_id) }.sort_by(&:to_s) }
    existing = entry.journal_lines.map { |l| l.attributes.symbolize_keys }
    signature.call(existing) == signature.call(normalized)
  end

  private_class_method :live_entry, :write!, :source_attributes, :normalize, :same?
end

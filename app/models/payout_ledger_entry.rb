# frozen_string_literal: true

# A single line in a performer's (or contractor's) company-wide payout ledger.
#
# A payee's balance with an organization is the SUM of amount_cents across their
# entries — always derived, never cached. This makes the balance impossible to
# drift (unlike the old PersonAdvance#remaining_balance cache).
#
# Sign convention:
#   earning   → positive  (org owes the payee more)
#   advance   → negative  (org already fronted money; nets against earnings)
#   payout    → negative  (money actually sent / recorded as paid)
#   adjustment/reversal → signed as needed
#
# Idempotency: `post!` upserts on (source, entry_type), so re-posting the same
# source (e.g. a payout line item on every recalculation) never double-counts.
class PayoutLedgerEntry < ApplicationRecord
  ENTRY_TYPES = %w[earning advance payout adjustment reversal].freeze
  # Which run scope an entry belongs to, so a run pays a payee's net owed *within
  # its scope*: "performer" (shows, contractors, advances — they share the
  # performer run) or "staffing" (staff pay, its own run/schedule).
  CATEGORIES = %w[performer staffing].freeze

  belongs_to :organization
  belongs_to :payee, polymorphic: true
  belongs_to :source, polymorphic: true, optional: true

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :category, inclusion: { in: CATEGORIES }
  validates :amount_cents, numericality: { only_integer: true }
  validates :currency, presence: true
  validates :occurred_at, presence: true

  scope :earnings, -> { where(entry_type: "earning") }
  scope :advances, -> { where(entry_type: "advance") }
  scope :payouts, -> { where(entry_type: "payout") }
  scope :for_payee, ->(payee) { where(payee: payee) }
  scope :for_category, ->(category) { category ? where(category: category) : all }

  # Idempotently record (or update) the ledger entry for a given source.
  # When a source + entry_type already exists, its amount/description are
  # refreshed in place — so recalculating a payout re-states the earning
  # rather than adding a second one.
  def self.post!(organization:, payee:, entry_type:, amount_cents:, source: nil,
                 description: nil, occurred_at: Time.current, currency: "usd", category: "performer")
    attrs = {
      organization: organization,
      payee: payee,
      amount_cents: amount_cents,
      description: description,
      occurred_at: occurred_at,
      currency: currency,
      category: category
    }

    if source
      entry = find_or_initialize_by(
        source_type: source.class.polymorphic_name,
        source_id: source.id,
        entry_type: entry_type
      )
      entry.assign_attributes(attrs)
      entry.save!
      entry
    else
      create!(attrs.merge(entry_type: entry_type))
    end
  end

  # Remove the entry a source posted (e.g. a payout was voided). Safe no-op if
  # nothing was posted.
  def self.unpost!(source:, entry_type:)
    return 0 unless source

    where(
      source_type: source.class.polymorphic_name,
      source_id: source.id,
      entry_type: entry_type
    ).delete_all
  end
end

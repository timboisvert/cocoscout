# frozen_string_literal: true

# One side of a journal entry: an amount (debit +, credit −) on one account,
# tagged with the show, production and payee it belongs to — the same slices
# CocoScout's money screens already use — and a fund for nonprofits'
# restricted money. Written once with its entry, never edited.
class JournalLine < ApplicationRecord
  belongs_to :journal_entry
  belongs_to :organization
  belongs_to :ledger_account
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :payee, polymorphic: true, optional: true

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }

  def readonly?
    persisted? || super
  end
end

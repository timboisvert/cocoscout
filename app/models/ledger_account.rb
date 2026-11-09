# frozen_string_literal: true

# One account in an organization's books ("Ticket income", "CocoScout
# balance"). Theaters never see these by name in the everyday money screens —
# they're the engine under them (see ChartOfAccounts for the set every org
# gets, and LedgerPosting for the only way money reaches them).
class LedgerAccount < ApplicationRecord
  TYPES = %w[asset liability equity income expense].freeze
  # Assets and expenses normally carry debit (+) balances; the rest credit (−).
  DEBIT_NORMAL = %w[asset expense].freeze

  belongs_to :organization
  has_many :journal_lines, dependent: :restrict_with_exception
  has_many :ledger_month_balances, dependent: :delete_all

  validates :code, :name, presence: true
  validates :account_type, inclusion: { in: TYPES }
  validates :code, uniqueness: { scope: :organization_id }
  validates :key, uniqueness: { scope: :organization_id }, allow_nil: true

  # The accounts every org gets are part of the books' shape.
  before_destroy { throw :abort if system? }

  scope :active, -> { where(active: true) }

  # Signed sum of the account's lines (debits +, credits −). Accrual counts an
  # entry on the day it was earned or incurred; cash counts it on the day the
  # money moved, and leaves out entries where it hasn't yet.
  # The finished months come from the balances kept for them (BooksBalances),
  # so this costs the same in year five as in month two.
  def balance_cents(as_of: nil, basis: :accrual)
    BooksBalances.sums(organization_id, basis: basis, to: as_of, account_ids: [ id ])[id].to_i
  end

  # The balance as a person reads it: positive when the account holds money on
  # its normal side (cash in the bank, income earned, tax owed).
  def natural_balance_cents(**options)
    signed = balance_cents(**options)
    DEBIT_NORMAL.include?(account_type) ? signed : -signed
  end
end

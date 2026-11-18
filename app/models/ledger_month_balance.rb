# frozen_string_literal: true

# What one account moved in one finished month (BooksBalances writes and
# reads these; nothing else should).
class LedgerMonthBalance < ApplicationRecord
  belongs_to :organization
  belongs_to :ledger_account
end

# frozen_string_literal: true

# How far an organization's month-end balances are kept (BooksBalances
# writes and reads this; nothing else should).
class BooksRollup < ApplicationRecord
  belongs_to :organization
end

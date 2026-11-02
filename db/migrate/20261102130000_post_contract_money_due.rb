# frozen_string_literal: true

# Contract money whose date has come goes on the books as owed, paid or not
# (BooksOutsidePoster). Data only; ContractMoneyDueJob keeps it up daily.
class PostContractMoneyDue < ActiveRecord::Migration[8.0]
  def up
    BooksOutsidePoster.post_contract_payments_due!
  end

  def down; end
end

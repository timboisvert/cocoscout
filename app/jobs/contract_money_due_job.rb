# frozen_string_literal: true

# Daily: contract money whose date has come goes on the books as owed, paid
# or not (BooksOutsidePoster.post_contract_payments_due!).
class ContractMoneyDueJob < ApplicationJob
  queue_as :default

  def perform
    BooksOutsidePoster.post_contract_payments_due!
  end
end

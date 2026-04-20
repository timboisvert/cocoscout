class AddShowIdToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :contract_payments, :show, null: true, foreign_key: true
  end
end

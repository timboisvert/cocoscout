class AddAmountTbdToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_payments, :amount_tbd, :boolean, default: false, null: false
  end
end

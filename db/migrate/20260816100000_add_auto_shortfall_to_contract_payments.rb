class AddAutoShortfallToContractPayments < ActiveRecord::Migration[8.1]
  def change
    # Marks a payment the shortfall sync owns: on a ticket-revenue-minus-fee
    # deal whose revenue came in under our fee, the difference is money they
    # still owe us. The sync keeps it in step with the show's financials, so it
    # has to be able to tell its own row from one someone added by hand.
    add_column :contract_payments, :auto_shortfall, :boolean, default: false, null: false
  end
end

class AddPayRunFieldsToPayoutBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batches, :kind, :string, null: false, default: "balance"
    add_column :payout_batches, :extra_payment_fee_cents, :integer, null: false, default: 0
    add_column :payout_batches, :payday, :date
  end
end

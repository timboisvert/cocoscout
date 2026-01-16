class RemovePaypalBatchIdFromShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    remove_column :show_payout_line_items, :paypal_batch_id, :string
  end
end

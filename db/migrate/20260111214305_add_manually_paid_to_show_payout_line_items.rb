class AddManuallyPaidToShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :show_payout_line_items, :manually_paid, :boolean, default: false, null: false
    add_column :show_payout_line_items, :manually_paid_at, :datetime
    add_reference :show_payout_line_items, :manually_paid_by, foreign_key: { to_table: :users }
  end
end

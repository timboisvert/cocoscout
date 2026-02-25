class AddArchivedAtToPayoutSchemes < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_schemes, :archived_at, :datetime
  end
end

class AddEffectiveFromToPayoutSchemes < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_schemes, :effective_from, :date
    add_index :payout_schemes, [ :production_id, :effective_from ]
    add_index :payout_schemes, [ :organization_id, :effective_from ]
  end
end

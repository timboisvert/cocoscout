class CreateTalentPoolShares < ActiveRecord::Migration[8.1]
  def change
    create_table :talent_pool_shares do |t|
      t.references :talent_pool, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true

      t.timestamps
    end

    add_index :talent_pool_shares, [ :talent_pool_id, :production_id ], unique: true
  end
end

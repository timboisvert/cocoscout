class CreateAdvanceRecoveries < ActiveRecord::Migration[8.1]
  def change
    create_table :advance_recoveries do |t|
      t.references :person_advance, null: false, foreign_key: true
      t.references :show_payout_line_item, null: false, foreign_key: true

      t.decimal :amount, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :advance_recoveries, [ :person_advance_id, :show_payout_line_item_id ],
              unique: true, name: "idx_advance_recoveries_unique"
  end
end

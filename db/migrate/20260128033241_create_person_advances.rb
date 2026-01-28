class CreatePersonAdvances < ActiveRecord::Migration[8.1]
  def change
    create_table :person_advances do |t|
      t.references :person, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.references :show, null: true, foreign_key: true, index: false  # Nullable for general advances
      t.references :issued_by, null: false, foreign_key: { to_table: :users }

      t.decimal :original_amount, precision: 10, scale: 2, null: false
      t.decimal :remaining_balance, precision: 10, scale: 2, null: false
      t.string :status, null: false, default: "pending"  # pending, partially_recovered, fully_recovered, written_off
      t.string :advance_type, null: false, default: "show"  # show, general
      t.text :notes

      t.datetime :issued_at, null: false
      t.datetime :fully_recovered_at

      t.timestamps
    end

    add_index :person_advances, [ :person_id, :production_id, :status ]
    add_index :person_advances, [ :show_id ], where: "show_id IS NOT NULL", name: "index_person_advances_on_show_id_partial"
  end
end

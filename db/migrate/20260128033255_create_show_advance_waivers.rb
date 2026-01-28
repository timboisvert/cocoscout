class CreateShowAdvanceWaivers < ActiveRecord::Migration[8.1]
  def change
    create_table :show_advance_waivers do |t|
      t.references :show, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :waived_by, null: false, foreign_key: { to_table: :users }

      t.string :reason, null: false  # no_advances_this_show, advance_carried_forward, performer_declined, other
      t.text :notes

      t.timestamps
    end

    add_index :show_advance_waivers, [ :show_id, :person_id ], unique: true
  end
end

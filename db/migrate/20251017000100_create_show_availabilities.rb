class CreateShowAvailabilities < ActiveRecord::Migration[7.0]
  def change
    create_table :show_availabilities do |t|
      t.references :person, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.timestamps
    end
    add_index :show_availabilities, [ :person_id, :show_id ], unique: true
  end
end

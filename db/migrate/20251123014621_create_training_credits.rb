class CreateTrainingCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :training_credits do |t|
      t.references :person, null: false, foreign_key: true
      t.string :institution, limit: 200, null: false
      t.string :program, limit: 200, null: false
      t.string :location, limit: 100
      t.integer :year_start, null: false
      t.integer :year_end
      t.text :notes, limit: 1000
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :training_credits, [ :person_id, :position ]
  end
end

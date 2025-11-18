class CreateQuestionnaires < ActiveRecord::Migration[8.1]
  def change
    create_table :questionnaires do |t|
      t.references :production, null: false, foreign_key: true
      t.string :title, null: false
      t.boolean :accepting_responses, default: true, null: false
      t.string :token, null: false, index: { unique: true }

      t.timestamps
    end

    add_index :questionnaires, [ :production_id, :title ]
  end
end

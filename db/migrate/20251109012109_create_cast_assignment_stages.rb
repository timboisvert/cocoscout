# frozen_string_literal: true

class CreateCastAssignmentStages < ActiveRecord::Migration[8.1]
  def change
    create_table :cast_assignment_stages do |t|
      t.references :production, null: false, foreign_key: true
      t.references :cast, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.text :notification_email

      t.timestamps
    end

    add_index :cast_assignment_stages, %i[production_id cast_id person_id], unique: true,
                                                                            name: 'index_cast_assignment_stages_unique'
  end
end

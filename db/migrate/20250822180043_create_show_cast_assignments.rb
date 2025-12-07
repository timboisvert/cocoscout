# frozen_string_literal: true

class CreateShowCastAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :show_cast_assignments do |t|
      t.references :show, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :cast_role, null: false, foreign_key: true

      t.timestamps
    end
  end
end

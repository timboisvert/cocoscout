# frozen_string_literal: true

class CreateStaffAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_availabilities do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.date :date, null: false
      # 0 unset, 1 available, 2 unavailable
      t.integer :status, null: false, default: 0
      t.string :note

      t.timestamps
    end

    add_index :staff_availabilities, %i[organization_id person_id date], unique: true,
              name: "idx_staff_availabilities_unique"
  end
end

# frozen_string_literal: true

class ReplaceStaffAvailabilitiesWithUnavailabilities < ActiveRecord::Migration[8.1]
  def up
    drop_table :staff_availabilities, if_exists: true

    create_table :staff_unavailabilities do |t|
      t.references :person, null: false, foreign_key: true
      t.date :date, null: false
      # 0 all_day, 1 day_shifts, 2 evening_shifts
      t.integer :scope, null: false, default: 0
      t.timestamps
    end

    add_index :staff_unavailabilities, %i[person_id date], unique: true,
              name: "idx_staff_unavailabilities_unique"
  end

  def down
    drop_table :staff_unavailabilities, if_exists: true

    create_table :staff_availabilities do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :status, null: false, default: 0
      t.string :note
      t.timestamps
    end
    add_index :staff_availabilities, %i[organization_id person_id date], unique: true,
              name: "idx_staff_availabilities_unique"
  end
end

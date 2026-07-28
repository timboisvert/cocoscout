# frozen_string_literal: true

# When a staff member who was ALREADY notified about a shift gets unassigned (or
# their shift is deleted), we record it here so the next "Notify updates" can tell
# them their shift was removed. Cleared (notified_at stamped) once they're told.
class CreateStaffScheduleRemovals < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_schedule_removals do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.datetime :shift_starts_at, null: false
      t.string :shift_label
      t.string :location_name
      t.datetime :notified_at
      t.timestamps
    end
    add_index :staff_schedule_removals, [:organization_id, :shift_starts_at]
  end
end

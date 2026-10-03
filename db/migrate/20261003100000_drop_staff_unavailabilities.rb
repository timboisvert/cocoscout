# frozen_string_literal: true

# The old staff availability (day marks in staff_unavailabilities, plus the
# people.availability_mode flag) was carried into time bands on 2026-09-19
# (CarryStaffAvailabilityIntoTimeBands, run in production 2026-09-29) and
# read by nothing since. Gone for good; the time bands are the record.
class DropStaffUnavailabilities < ActiveRecord::Migration[8.1]
  def up
    drop_table :staff_unavailabilities
    remove_column :people, :availability_mode
  end

  def down
    add_column :people, :availability_mode, :string, default: "unavailable", null: false
    create_table :staff_unavailabilities do |t|
      t.date :date, null: false
      t.string :day_part_key
      t.bigint :person_id, null: false
      t.integer :scope, default: 0, null: false
      t.timestamps
      t.index %i[person_id date], name: "idx_staff_unavailabilities_unique", unique: true
      t.index :person_id
    end
  end
end

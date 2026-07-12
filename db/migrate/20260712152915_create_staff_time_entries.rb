class CreateStaffTimeEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_time_entries do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      # Set when confirming a scheduled shift; null for ad-hoc / self-logged time.
      t.references :shift_assignment, null: true, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.decimal :hours, precision: 6, scale: 2, null: false
      t.string :source, null: false, default: "manual"
      t.string :notes
      # Set when the entry is pulled into a pay run (leaves the "unpaid" pool).
      t.references :payout_batch, null: true, foreign_key: true
      t.datetime :paid_at

      t.timestamps
    end

    # One confirmation per shift assignment.
    add_index :staff_time_entries, :shift_assignment_id, unique: true,
              where: "shift_assignment_id IS NOT NULL",
              name: "idx_staff_time_entries_unique_assignment"
  end
end

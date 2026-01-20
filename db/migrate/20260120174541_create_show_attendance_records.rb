class CreateShowAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :show_attendance_records do |t|
      t.references :show, null: false, foreign_key: true
      t.references :show_person_role_assignment, null: false, foreign_key: true
      t.string :status, null: false, default: "unknown"  # present, absent, late, excused, unknown
      t.datetime :checked_in_at
      t.text :notes

      t.timestamps
    end

    add_index :show_attendance_records, [ :show_id, :show_person_role_assignment_id ], unique: true, name: "idx_attendance_show_assignment"
  end
end

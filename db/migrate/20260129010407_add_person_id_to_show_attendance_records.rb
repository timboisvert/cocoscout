# frozen_string_literal: true

class AddPersonIdToShowAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    # Add person_id for walk-ins (optional - only used for walk-ins)
    add_reference :show_attendance_records, :person, null: true, foreign_key: true

    # Add unique index for walk-in attendance (one record per person per show)
    add_index :show_attendance_records, [ :show_id, :person_id ],
              unique: true,
              where: "person_id IS NOT NULL",
              name: "idx_attendance_by_walkin"

    # Convert any "late" status to "present" since we're removing late
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE show_attendance_records SET status = 'present' WHERE status = 'late'
        SQL
      end
    end
  end
end

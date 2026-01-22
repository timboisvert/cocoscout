class UpdateShowAttendanceRecordsForSignUps < ActiveRecord::Migration[8.1]
  def change
    # Make show_person_role_assignment_id optional since attendance can also be for sign-ups
    change_column :show_attendance_records, :show_person_role_assignment_id, :bigint, null: true

    # Add column to track sign_up_registration attendance
    add_column :show_attendance_records, :sign_up_registration_id, :bigint
    add_foreign_key :show_attendance_records, :sign_up_registrations, column: :sign_up_registration_id

    # Add unique constraint: either assignment_id OR registration_id per show (but not both)
    add_index :show_attendance_records, [ :show_id, :show_person_role_assignment_id ], unique: true, where: "show_person_role_assignment_id IS NOT NULL", name: 'idx_attendance_by_assignment'
    add_index :show_attendance_records, [ :show_id, :sign_up_registration_id ], unique: true, where: "sign_up_registration_id IS NOT NULL", name: 'idx_attendance_by_signup'
  end
end

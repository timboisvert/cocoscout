class AddInstructorPersonToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offerings, :instructor_person_id, :bigint
    add_index :course_offerings, :instructor_person_id
    add_foreign_key :course_offerings, :people, column: :instructor_person_id, on_delete: :nullify
  end
end

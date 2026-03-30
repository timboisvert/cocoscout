class AddInstructorPrefaceToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offerings, :instructor_preface, :text
  end
end

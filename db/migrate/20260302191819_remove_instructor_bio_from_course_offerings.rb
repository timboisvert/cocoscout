class RemoveInstructorBioFromCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    remove_column :course_offerings, :instructor_bio, :text
  end
end

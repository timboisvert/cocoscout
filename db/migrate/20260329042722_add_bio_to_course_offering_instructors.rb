class AddBioToCourseOfferingInstructors < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offering_instructors, :bio, :text
  end
end

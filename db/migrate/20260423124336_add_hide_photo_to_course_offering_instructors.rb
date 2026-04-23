class AddHidePhotoToCourseOfferingInstructors < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offering_instructors, :hide_photo, :boolean, default: false, null: false
  end
end

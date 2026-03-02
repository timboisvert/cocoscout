class RemoveDescriptionFromCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    remove_column :course_offerings, :description, :text
  end
end

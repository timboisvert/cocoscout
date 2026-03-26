class AddListedInDirectoryToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offerings, :listed_in_directory, :boolean, default: true, null: false
  end
end

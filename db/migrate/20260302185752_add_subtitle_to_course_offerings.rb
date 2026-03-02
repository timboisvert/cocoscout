class AddSubtitleToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offerings, :subtitle, :string
  end
end

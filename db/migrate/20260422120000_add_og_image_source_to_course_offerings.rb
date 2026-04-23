class AddOgImageSourceToCourseOfferings < ActiveRecord::Migration[8.0]
  def change
    add_column :course_offerings, :og_image_source, :string, default: "auto", null: false
  end
end

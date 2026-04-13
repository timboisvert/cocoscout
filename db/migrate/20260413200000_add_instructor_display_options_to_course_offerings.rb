# frozen_string_literal: true

class AddInstructorDisplayOptionsToCourseOfferings < ActiveRecord::Migration[8.0]
  def change
    add_column :course_offerings, :show_individual_photos, :boolean, default: true, null: false
    add_column :course_offerings, :show_individual_bios, :boolean, default: true, null: false
    add_column :course_offerings, :show_group_photo, :boolean, default: false, null: false
    add_column :course_offerings, :show_group_bio, :boolean, default: true, null: false
  end
end

class AddInstructorOnTeamToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offerings, :instructor_on_team, :boolean, default: false, null: false
  end
end

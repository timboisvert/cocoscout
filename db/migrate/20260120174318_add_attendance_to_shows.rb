class AddAttendanceToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :attendance_enabled, :boolean, default: false, null: false  end
end

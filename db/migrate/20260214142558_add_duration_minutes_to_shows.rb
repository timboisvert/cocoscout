class AddDurationMinutesToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :duration_minutes, :integer
  end
end

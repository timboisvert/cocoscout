class AddRecurrencePatternToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :recurrence_pattern, :string
  end
end

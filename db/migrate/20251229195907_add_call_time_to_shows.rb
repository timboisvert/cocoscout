class AddCallTimeToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :call_time, :datetime
    add_column :shows, :call_time_enabled, :boolean, default: false, null: false
  end
end

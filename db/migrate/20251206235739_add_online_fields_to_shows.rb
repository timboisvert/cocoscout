class AddOnlineFieldsToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :is_online, :boolean, default: false, null: false
    add_column :shows, :online_location_info, :string
  end
end

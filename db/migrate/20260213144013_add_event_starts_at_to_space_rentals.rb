class AddEventStartsAtToSpaceRentals < ActiveRecord::Migration[8.1]
  def change
    add_column :space_rentals, :event_starts_at, :datetime
  end
end

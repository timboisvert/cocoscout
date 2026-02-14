class AddEventEndsAtToSpaceRentals < ActiveRecord::Migration[8.1]
  def change
    add_column :space_rentals, :event_ends_at, :datetime
  end
end

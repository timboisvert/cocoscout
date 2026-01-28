class AddLocationToSpaceRentals < ActiveRecord::Migration[8.1]
  def change
    # Add location_id (optional initially for backfill, then required)
    add_reference :space_rentals, :location, null: true, foreign_key: true

    # Backfill location_id from location_space
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE space_rentals
          SET location_id = (
            SELECT location_id FROM location_spaces
            WHERE location_spaces.id = space_rentals.location_space_id
          )
          WHERE location_space_id IS NOT NULL
        SQL
      end
    end

    # Make location_id required after backfill
    change_column_null :space_rentals, :location_id, false

    # Make location_space_id nullable (for "Entire venue" bookings)
    change_column_null :space_rentals, :location_space_id, true
  end
end

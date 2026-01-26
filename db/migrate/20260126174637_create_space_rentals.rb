class CreateSpaceRentals < ActiveRecord::Migration[8.1]
  def change
    create_table :space_rentals do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :location_space, null: false, foreign_key: true

      # Booking time
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      # Rental details
      t.text :notes
      t.boolean :confirmed, default: false, null: false

      t.timestamps
    end

    add_index :space_rentals, %i[location_space_id starts_at ends_at], name: "index_space_rentals_on_space_and_time"
    add_index :space_rentals, :starts_at
  end
end

class AddLocationSpaceToShows < ActiveRecord::Migration[8.1]
  def change
    add_reference :shows, :location_space, null: true, foreign_key: true
    add_reference :shows, :space_rental, null: true, foreign_key: true
  end
end

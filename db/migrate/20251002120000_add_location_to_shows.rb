class AddLocationToShows < ActiveRecord::Migration[7.0]
  def change
    add_reference :shows, :location, foreign_key: true
  end
end

class AddLocationToSeatingConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_reference :seating_configurations, :location, null: true, foreign_key: true
  end
end

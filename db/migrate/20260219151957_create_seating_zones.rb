class CreateSeatingZones < ActiveRecord::Migration[8.1]
  def change
    create_table :seating_zones do |t|
      t.references :seating_configuration, null: false, foreign_key: true
      t.string :name, null: false
      t.string :zone_type, null: false
      t.integer :unit_count, null: false, default: 1
      t.integer :capacity_per_unit, null: false, default: 1
      t.integer :total_capacity, null: false, default: 1
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :seating_zones, [ :seating_configuration_id, :position ]
  end
end

class CreateLocationSpaces < ActiveRecord::Migration[8.1]
  def change
    create_table :location_spaces do |t|
      t.references :location, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :capacity
      t.boolean :default, default: false, null: false

      t.timestamps
    end

    add_index :location_spaces, %i[location_id default], unique: true, where: '"default" = true', name: "index_location_spaces_one_default_per_location"
  end
end

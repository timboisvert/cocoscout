class AddIsPrimaryToPosters < ActiveRecord::Migration[8.1]
  def change
    add_column :posters, :is_primary, :boolean, default: false, null: false
    add_index :posters, [ :production_id, :is_primary ], where: "is_primary = true", unique: true, name: "index_posters_on_production_id_primary"
  end
end

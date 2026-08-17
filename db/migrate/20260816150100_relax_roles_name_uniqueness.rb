class RelaxRolesNameUniqueness < ActiveRecord::Migration[8.0]
  # An act-based lineup can repeat a name ("Magic" in each half of the show),
  # so name uniqueness moves from the database to a mode-aware model
  # validation. Keep the index for lookups, just not unique.
  def change
    remove_index :roles, name: "index_roles_on_production_show_name"
    add_index :roles, [ :production_id, :show_id, :name ], name: "index_roles_on_production_show_name"
  end
end

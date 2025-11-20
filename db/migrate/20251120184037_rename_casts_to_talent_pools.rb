class RenameCastsToTalentPools < ActiveRecord::Migration[8.1]
  def change
    # Rename main table
    rename_table :casts, :talent_pools

    # Rename join table
    rename_table :casts_people, :people_talent_pools

    # Rename foreign key columns in join table
    rename_column :people_talent_pools, :cast_id, :talent_pool_id

    # Rename index on the join table
    remove_index :people_talent_pools, name: "index_people_talent_pools_on_cast_id"
    add_index :people_talent_pools, :talent_pool_id, name: "index_people_talent_pools_on_talent_pool_id"

    # Rename columns in other tables that reference casts
    rename_column :cast_assignment_stages, :cast_id, :talent_pool_id
  end
end

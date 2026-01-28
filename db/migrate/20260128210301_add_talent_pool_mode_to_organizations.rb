class AddTalentPoolModeToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # talent_pool_mode: 'per_production' (default) or 'single'
    add_column :organizations, :talent_pool_mode, :string, default: 'per_production', null: false
    
    # Reference to the organization-level talent pool (used when mode is 'single')
    # This is nullable - only set when switching to single mode
    add_reference :organizations, :organization_talent_pool, null: true, foreign_key: { to_table: :talent_pools }
    
    add_index :organizations, :talent_pool_mode
  end
end

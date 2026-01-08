class RemoveFeatureFlagsFromProductions < ActiveRecord::Migration[8.1]
  def change
    remove_column :productions, :has_talent_pool, :boolean, default: true, null: false
    remove_column :productions, :has_roles, :boolean, default: true, null: false
    remove_column :productions, :has_auditions, :boolean, default: true, null: false
  end
end

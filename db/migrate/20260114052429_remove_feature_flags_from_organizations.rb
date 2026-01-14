class RemoveFeatureFlagsFromOrganizations < ActiveRecord::Migration[8.1]
  def change
    remove_column :organizations, :feature_auditions, :boolean
    remove_column :organizations, :feature_signups, :boolean
    remove_column :organizations, :feature_money, :boolean
  end
end

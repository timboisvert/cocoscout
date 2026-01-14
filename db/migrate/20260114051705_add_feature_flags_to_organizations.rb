class AddFeatureFlagsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :feature_auditions, :boolean, default: true, null: false
    add_column :organizations, :feature_signups, :boolean, default: true, null: false
    add_column :organizations, :feature_money, :boolean, default: false, null: false
  end
end

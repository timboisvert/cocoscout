class AddPublicProfileEnabledToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :public_profile_enabled, :boolean, default: true, null: false
  end
end

class AddForumModeToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :forum_mode, :string, default: "per_production", null: false
  end
end

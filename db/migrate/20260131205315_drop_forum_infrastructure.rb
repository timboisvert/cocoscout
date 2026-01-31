class DropForumInfrastructure < ActiveRecord::Migration[8.1]
  def change
    # Drop forum tables
    drop_table :post_views, if_exists: true
    drop_table :posts, if_exists: true

    # Remove forum fields from organizations
    remove_column :organizations, :forum_mode, :string, if_exists: true
    remove_column :organizations, :shared_forum_name, :string, if_exists: true

    # Remove forum fields from productions
    remove_column :productions, :forum_enabled, :boolean, if_exists: true
  end
end

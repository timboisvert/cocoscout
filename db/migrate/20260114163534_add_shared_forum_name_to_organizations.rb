class AddSharedForumNameToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :shared_forum_name, :string
  end
end

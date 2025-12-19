class AddShowOnProfileToGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :group_memberships, :show_on_profile, :boolean, default: true, null: false
  end
end

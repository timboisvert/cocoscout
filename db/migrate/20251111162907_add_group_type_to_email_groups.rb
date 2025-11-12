class AddGroupTypeToEmailGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :email_groups, :group_type, :string
  end
end

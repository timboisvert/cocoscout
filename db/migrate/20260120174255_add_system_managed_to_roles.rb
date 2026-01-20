class AddSystemManagedToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :system_managed, :boolean, default: false, null: false
    add_column :roles, :system_role_type, :string
  end
end

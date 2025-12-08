class AddRestrictedToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :restricted, :boolean, default: false, null: false
  end
end

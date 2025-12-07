# frozen_string_literal: true

class RenameRoleToDefaultRoleInUserRoles < ActiveRecord::Migration[8.1]
  def change
    rename_column :user_roles, :role, :default_role
  end
end

# frozen_string_literal: true

class RenameUserRolesToOrganizationRoles < ActiveRecord::Migration[8.1]
  def change
    rename_table :user_roles, :organization_roles
  end
end

# frozen_string_literal: true

class RenameDefaultRoleToCompanyRole < ActiveRecord::Migration[8.1]
  def change
    rename_column :user_roles, :default_role, :company_role
  end
end

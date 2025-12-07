# frozen_string_literal: true

class RenameCastRolesToRoles < ActiveRecord::Migration[8.0]
  def change
    rename_table :cast_roles, :roles
  end
end

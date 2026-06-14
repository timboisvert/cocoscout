# frozen_string_literal: true

# Distinguishes house roles (one shift spanning the whole evening, e.g.
# bartender) from show-specific roles (one shift per show/rehearsal, e.g. tech)
# so generation and display can treat them differently.
class AddRoleTypeToHouseRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :house_roles, :role_type, :integer, default: 0, null: false
  end
end

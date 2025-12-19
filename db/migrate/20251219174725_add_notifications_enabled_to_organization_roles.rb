class AddNotificationsEnabledToOrganizationRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_roles, :notifications_enabled, :boolean
  end
end

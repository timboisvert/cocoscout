class AddNotificationsEnabledToProductionPermissions < ActiveRecord::Migration[8.1]
  def change
    add_column :production_permissions, :notifications_enabled, :boolean
  end
end

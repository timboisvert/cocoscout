# frozen_string_literal: true

class CreateProductionNotificationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :production_notification_settings do |t|
      t.references :production, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :production_notification_settings, [ :production_id, :user_id ],
              unique: true, name: "idx_prod_notif_settings_on_prod_and_user"

    reversible do |dir|
      dir.up do
        # Migrate existing production permission notification preferences
        execute <<-SQL
          INSERT INTO production_notification_settings (production_id, user_id, enabled, created_at, updated_at)
          SELECT production_id, user_id,
                 CASE
                   WHEN notifications_enabled IS NOT NULL THEN notifications_enabled
                   WHEN role = 'manager' THEN true
                   ELSE false
                 END,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM production_permissions
        SQL

        # For org members (managers/viewers) who don't have a production permission,
        # create notification settings for all productions in their org
        execute <<-SQL
          INSERT INTO production_notification_settings (production_id, user_id, enabled, created_at, updated_at)
          SELECT p.id, org_r.user_id,
                 CASE
                   WHEN org_r.notifications_enabled IS NOT NULL THEN org_r.notifications_enabled
                   WHEN org_r.company_role = 'manager' THEN true
                   ELSE false
                 END,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM productions p
          INNER JOIN organization_roles org_r ON org_r.organization_id = p.organization_id
          WHERE org_r.company_role IN ('manager', 'viewer')
          AND NOT EXISTS (
            SELECT 1 FROM production_notification_settings pns
            WHERE pns.production_id = p.id AND pns.user_id = org_r.user_id
          )
        SQL

        # Also include org owners who might not have an org role record
        execute <<-SQL
          INSERT INTO production_notification_settings (production_id, user_id, enabled, created_at, updated_at)
          SELECT p.id, o.owner_id, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM productions p
          INNER JOIN organizations o ON o.id = p.organization_id
          WHERE o.owner_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM production_notification_settings pns
            WHERE pns.production_id = p.id AND pns.user_id = o.owner_id
          )
        SQL
      end
    end

    remove_column :production_permissions, :notifications_enabled, :boolean
    remove_column :organization_roles, :notifications_enabled, :boolean
  end
end

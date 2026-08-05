# frozen_string_literal: true

# The shoutout feature is gone. In the eight months it was live exactly one
# shoutout was ever written, so there is nothing here worth keeping: this drops
# the table, deletes the content templates that fed it, and strips the dead
# `shoutouts` key out of every user's notification preferences.
#
# Irreversible on purpose — `up` throws away the rows, so a rebuild starts fresh.
class DropShoutouts < ActiveRecord::Migration[8.1]
  def up
    drop_table :shoutouts

    execute <<~SQL.squish
      DELETE FROM content_templates
      WHERE key IN ('shoutout_notification', 'shoutout_invitation', 'shoutout_received')
    SQL

    execute <<~SQL.squish
      UPDATE users
      SET notification_preferences = notification_preferences - 'shoutouts'
      WHERE jsonb_exists(notification_preferences, 'shoutouts')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

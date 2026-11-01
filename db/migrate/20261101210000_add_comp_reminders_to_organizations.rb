# frozen_string_literal: true

# Which comp-ending reminders an organization has had, per comp end date
# ({ "2026-12-31" => ["two_weeks", "three_days"] }), so each goes once; and
# the email they get (ProCompEnding).
class AddCompRemindersToOrganizations < ActiveRecord::Migration[8.0]
  def up
    add_column :organizations, :comp_reminders, :jsonb, default: {}, null: false
    PlatformTemplates.ensure!(keys: %w[pro_comp_ending])
  end

  def down
    remove_column :organizations, :comp_reminders
    ContentTemplate.where(key: "pro_comp_ending").delete_all
  end
end

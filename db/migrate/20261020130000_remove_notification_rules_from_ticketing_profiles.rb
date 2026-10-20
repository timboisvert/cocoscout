# frozen_string_literal: true

# Ticketing notifications are per-person plans now (notification_plans);
# 20261020120000 copied every organization's choices across. Tim, 2026-10-20:
# with only a few users, drop the old column rather than keep it around.
class RemoveNotificationRulesFromTicketingProfiles < ActiveRecord::Migration[8.1]
  def up
    remove_column :ticketing_profiles, :notification_rules
  end

  def down
    add_column :ticketing_profiles, :notification_rules, :jsonb, null: false, default: {}
  end
end

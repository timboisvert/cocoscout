# frozen_string_literal: true

# Which managers get an in-app message when a contract is signed. Stored as a list
# of user ids; empty means "all managers" (so a newly-added manager is covered
# without re-visiting settings). Mirrors the other jsonb list settings.
class AddContractNotificationUserIdsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :contract_notification_user_ids, :jsonb, default: [], null: false
  end
end

# frozen_string_literal: true

# Which managers get an email when a payout run is submitted (funded) —
# mirrors contract_notification_user_ids. Empty = nobody gets emailed.
class AddPayoutNotificationUserIdsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :payout_notification_user_ids, :jsonb, default: [], null: false
  end
end

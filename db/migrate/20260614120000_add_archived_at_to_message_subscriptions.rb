# frozen_string_literal: true

# Per-user thread archiving. The inbox is built from subscriptions, so archiving
# belongs here (the old message_recipients.archived_at never affected the inbox).
class AddArchivedAtToMessageSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :message_subscriptions, :archived_at, :datetime
    add_index :message_subscriptions, [ :user_id, :archived_at ]
  end
end

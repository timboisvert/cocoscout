class AddUnreadCountToMessageSubscriptions < ActiveRecord::Migration[8.1]
  def up
    add_column :message_subscriptions, :unread_count, :integer, default: 0, null: false
    add_index :message_subscriptions, [ :user_id, :unread_count ], name: "index_message_subscriptions_on_user_id_and_unread_count"

    # Backfill unread counts for existing subscriptions
    # For each subscription, count messages in the thread newer than last_read_at
    execute <<-SQL
      UPDATE message_subscriptions
      SET unread_count = (
        WITH RECURSIVE thread_messages AS (
          SELECT id, created_at, sender_id, sender_type FROM messages WHERE id = message_subscriptions.message_id AND deleted_at IS NULL
          UNION ALL
          SELECT m.id, m.created_at, m.sender_id, m.sender_type FROM messages m
          INNER JOIN thread_messages tm ON m.parent_message_id = tm.id
          WHERE m.deleted_at IS NULL
        )
        SELECT COUNT(*) FROM thread_messages
        WHERE (message_subscriptions.last_read_at IS NULL OR created_at > message_subscriptions.last_read_at)
        AND NOT (sender_type = 'User' AND sender_id = message_subscriptions.user_id)
      )
    SQL
  end

  def down
    remove_index :message_subscriptions, name: "index_message_subscriptions_on_user_id_and_unread_count"
    remove_column :message_subscriptions, :unread_count
  end
end

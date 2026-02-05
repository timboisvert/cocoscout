class MessageSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :message  # The root message of the thread

  validates :user_id, uniqueness: { scope: :message_id }

  scope :active, -> { where(muted: false) }
  scope :muted, -> { where(muted: true) }

  # Scope version of unread? - finds subscriptions where:
  # - last_read_at is NULL, OR
  # - there are messages in the thread (root + all descendants) created after last_read_at
  # Uses recursive CTE to find all descendants at any nesting level
  scope :unread, -> {
    active.where(
      "message_subscriptions.last_read_at IS NULL OR EXISTS (
        WITH RECURSIVE thread_messages AS (
          SELECT id, created_at FROM messages WHERE id = message_subscriptions.message_id AND deleted_at IS NULL
          UNION ALL
          SELECT m.id, m.created_at FROM messages m
          INNER JOIN thread_messages tm ON m.parent_message_id = tm.id
          WHERE m.deleted_at IS NULL
        )
        SELECT 1 FROM thread_messages WHERE created_at > message_subscriptions.last_read_at
      )"
    )
  }

  def mute!
    update!(muted: true)
  end

  def unmute!
    update!(muted: false)
  end

  def mark_read!
    update!(last_read_at: Time.current)
  end

  def unread?
    return true if last_read_at.nil?

    # Check if root message or any descendants are newer than last_read_at
    # Match the logic in the unread scope
    descendant_ids = message.descendant_ids
    Message.where(id: [ message.id ] + descendant_ids)
           .where(deleted_at: nil)
           .where("created_at > ?", last_read_at)
           .exists?
  end
end

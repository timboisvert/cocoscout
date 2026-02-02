class MessageSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :message  # The root message of the thread

  validates :user_id, uniqueness: { scope: :message_id }

  scope :active, -> { where(muted: false) }
  scope :muted, -> { where(muted: true) }
  scope :unread, -> {
    joins(:message).where(
      "message_subscriptions.last_read_at IS NULL OR messages.updated_at > message_subscriptions.last_read_at"
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
    descendant_ids = message.descendant_ids
    Message.where(id: [ message.id ] + descendant_ids)
           .where("created_at > ?", last_read_at)
           .exists?
  end
end

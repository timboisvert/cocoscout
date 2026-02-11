class MessageSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :message  # The root message of the thread

  validates :user_id, uniqueness: { scope: :message_id }

  scope :active, -> { where(muted: false) }
  scope :muted, -> { where(muted: true) }

  # Optimized scope using counter cache column
  scope :unread, -> { active.where("unread_count > 0") }

  def mute!
    update!(muted: true)
  end

  def unmute!
    update!(muted: false)
  end

  def mark_read!
    return if unread_count.zero? && last_read_at.present?

    transaction do
      update!(last_read_at: Time.current, unread_count: 0)
      UserNotificationsChannel.broadcast_unread_count(user)
    end
  end

  # Increment unread count when a new message arrives in this thread
  # Called from Message after_create callback
  def increment_unread!
    increment!(:unread_count)
  end

  def unread?
    unread_count > 0
  end
end

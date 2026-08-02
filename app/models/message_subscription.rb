class MessageSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :message  # The root message of the thread

  validates :user_id, uniqueness: { scope: :message_id }

  scope :active, -> { where(muted: false) }
  scope :muted, -> { where(muted: true) }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Optimized scope using counter cache column. Archived threads don't count
  # toward unread (they've been set aside).
  scope :unread, -> { active.not_archived.where("unread_count > 0") }

  def mute!
    update!(muted: true)
  end

  def unmute!
    update!(muted: false)
  end

  def archive!
    update!(archived_at: Time.current) if archived_at.nil?
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def archived?
    archived_at.present?
  end

  def mark_read!
    return if unread_count.zero? && last_read_at.present?

    update!(last_read_at: Time.current, unread_count: 0)
  end

  # Inverse of mark_read! — flip the thread back to "unread" so it reappears in
  # the inbox unread filter and re-increments the sidebar badge.
  def mark_unread!
    update!(last_read_at: nil, unread_count: [ unread_count, 1 ].max)
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

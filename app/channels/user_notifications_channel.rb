# Channel for user-specific notifications (unread counts, new messages)
class UserNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def unsubscribed
    # Any cleanup needed when user disconnects
  end

  # Class method to broadcast unread count update to a user
  def self.broadcast_unread_count(user)
    broadcast_to(
      user,
      {
        type: "unread_count",
        count: user.unread_message_count
      }
    )
  rescue ArgumentError => e
    # Solid Cable in Rails 8.1 has upsert compatibility issues
    Rails.logger.warn("UserNotificationsChannel.broadcast_unread_count failed: #{e.message}")
  end

  # Class method to notify user of a new message
  def self.broadcast_new_message(user, message, thread_subject = nil)
    broadcast_to(
      user,
      {
        type: "new_message",
        message_id: message.id,
        thread_id: message.root_message.id,
        subject: thread_subject || message.root_message.subject,
        sender_name: message.sender_name,
        preview: message.body.to_plain_text.truncate(100),
        message_url: Rails.application.routes.url_helpers.my_message_path(message.root_message)
      }
    )
  rescue ArgumentError => e
    # Solid Cable in Rails 8.1 has upsert compatibility issues
    Rails.logger.warn("UserNotificationsChannel.broadcast_new_message failed: #{e.message}")
  end
end

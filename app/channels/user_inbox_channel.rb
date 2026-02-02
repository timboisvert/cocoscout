# frozen_string_literal: true

class UserInboxChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def unsubscribed
    # Cleanup when user disconnects
  end

  # Broadcast a new message notification to a user's inbox
  def self.broadcast_new_message(user, message)
    broadcast_to(user, {
      type: "new_message",
      message_id: message.id,
      root_message_id: message.root_message.id,
      subject: message.root_message.subject,
      sender_name: message.sender_name,
      is_reply: message.parent_message_id.present?
    })
  end
end

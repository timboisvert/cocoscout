# frozen_string_literal: true

# Push notifications to the CocoScout app. Every new message a person is
# subscribed to pushes (Message#notify_subscribers), unless they muted the
# thread. Sending happens in PushDeliveryJob, never on the request.
class PushNotificationService
  # Queue a notification for all of a user's phones.
  #
  #   title, body - what the notification says
  #   data        - our own keys; "path" is the page a tap opens
  #   badge       - the number on the app icon (unread messages)
  def self.notify(user, title:, body:, data: {}, badge: nil)
    return unless user.device_tokens.exists?

    PushDeliveryJob.perform_later(user.id, { "title" => title, "body" => body,
                                             "data" => data.deep_stringify_keys, "badge" => badge }.compact)
  end

  # A new message in one of their threads: who sent it, the start of it, and
  # a tap opens the thread.
  def self.notify_new_message(user, message)
    return unless user.device_tokens.exists?

    root = message.root_message
    notify(
      user,
      title: message.sender_name,
      body: message.body.to_plain_text.squish.truncate(140),
      data: {
        type: "new_message",
        path: Rails.application.routes.url_helpers.my_message_path(root),
        thread_id: root.id.to_s,
        message_id: message.id.to_s
      },
      badge: user.unread_message_count
    )
  end
end

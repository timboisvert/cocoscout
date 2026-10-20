# frozen_string_literal: true

# Push notifications to the CocoScout app. A new message pushes to the people
# it is for (Message#notify_subscribers decides who), unless they muted the
# thread. Sending happens in PushDeliveryJob, never on the request.
class PushNotificationService
  # Queue a notification for all of a user's phones.
  #
  #   title, body - what the notification says; subtitle is the smaller line
  #                 under the title on iPhones
  #   data        - our own keys; "path" is the page a tap opens
  #   badge       - the number on the app icon (unread messages)
  def self.notify(user, title:, body:, subtitle: nil, data: {}, badge: nil)
    return unless user.device_tokens.exists?

    PushDeliveryJob.perform_later(user.id, { "title" => title, "subtitle" => subtitle, "body" => body,
                                             "data" => data.deep_stringify_keys, "badge" => badge }.compact)
  end

  # A new message in one of their threads; a tap opens the thread.
  #
  # An automated notice (one made from a content template) reads like the
  # production is talking: title = production name (else CocoScout), body = the
  # template's push text. A message a person wrote reads like a text from them:
  # title = their name, subtitle = the production, body = what they wrote.
  def self.notify_new_message(user, message)
    return unless user.device_tokens.exists?
    return unless user.message_push?

    root = message.root_message
    production_name = message.effective_production&.name
    if message.automated?
      title = production_name || "CocoScout"
      subtitle = nil
      body = message.push_body.presence || message.subject
    else
      title = author_name(message)
      subtitle = production_name
      body = message.body.to_plain_text.squish.truncate(140)
    end

    notify(
      user,
      title: title,
      subtitle: subtitle,
      body: body,
      data: {
        type: "new_message",
        path: Rails.application.routes.url_helpers.my_message_path(root),
        thread_id: root.id.to_s,
        message_id: message.id.to_s
      },
      badge: user.unread_message_count + user.unread_notification_count
    )
  end

  # The person who wrote it, even on a thread the inbox files under the
  # production's name.
  def self.author_name(message)
    case message.sender
    when User then message.sender.person&.name || message.sender.email_address
    when Person then message.sender.name
    else message.sender_name
    end
  end
end

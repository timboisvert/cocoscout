# frozen_string_literal: true

class PushNotificationService
  # Send a push notification to all of a user's registered devices.
  #
  # Arguments:
  #   user       - User record (must have device_tokens association)
  #   title      - Notification title string
  #   body       - Notification body string
  #   data       - Hash of custom data (e.g. { path: "/my/messages/123" })
  #   badge      - Integer badge count (iOS only, optional)
  #
  def self.notify(user, title:, body:, data: {}, badge: nil)
    return if user.device_tokens.none?

    user.device_tokens.find_each do |device_token|
      case device_token.platform
      when "ios"
        deliver_apns(device_token, title: title, body: body, data: data, badge: badge)
      when "android"
        deliver_fcm(device_token, title: title, body: body, data: data)
      end
    end
  end

  # Convenience: push a new message notification, mirroring UserNotificationsChannel.broadcast_new_message
  def self.notify_new_message(user, message)
    root = message.root_message
    notify(
      user,
      title: message.sender_name,
      body: message.body.to_plain_text.truncate(100),
      data: {
        type: "new_message",
        path: Rails.application.routes.url_helpers.my_message_path(root),
        thread_id: root.id.to_s,
        message_id: message.id.to_s
      },
      badge: user.unread_message_count
    )
  end

  # Convenience: push a badge-count-only update (silent notification)
  def self.notify_unread_count(user)
    count = user.unread_message_count
    user.device_tokens.where(platform: "ios").find_each do |device_token|
      deliver_apns(device_token, title: nil, body: nil, data: { type: "unread_count" }, badge: count, content_available: true)
    end
  end

  class << self
    private

    def deliver_apns(device_token, title:, body:, data:, badge: nil, content_available: false)
      app = rpush_apns_app
      return unless app

      notification = Rpush::Apns2::Notification.new
      notification.app = app
      notification.device_token = device_token.token
      notification.alert = { title: title, body: body } if title.present?
      notification.data = data
      notification.sound = "default" if title.present?
      notification.badge = badge if badge
      notification.content_available = true if content_available
      notification.save!
    rescue => e
      Rails.logger.error("PushNotificationService APNs error: #{e.message}")
      handle_invalid_token(device_token, e)
    end

    def deliver_fcm(device_token, title:, body:, data:)
      app = rpush_fcm_app
      return unless app

      notification = Rpush::Fcm::Notification.new
      notification.app = app
      notification.device_token = device_token.token
      notification.registration_ids = [ device_token.token ]
      notification.notification = { title: title, body: body }
      notification.data = data
      notification.save!
    rescue => e
      Rails.logger.error("PushNotificationService FCM error: #{e.message}")
      handle_invalid_token(device_token, e)
    end

    def rpush_apns_app
      Rpush::Apns2::App.find_by(name: "cocoscout_ios")
    end

    def rpush_fcm_app
      Rpush::Fcm::App.find_by(name: "cocoscout_android")
    end

    # Remove tokens that APNs/FCM report as invalid
    def handle_invalid_token(device_token, error)
      if error.message.include?("InvalidToken") ||
         error.message.include?("Unregistered") ||
         error.message.include?("NotRegistered")
        device_token.destroy
        Rails.logger.info("PushNotificationService: removed invalid device token #{device_token.id}")
      end
    end
  end
end

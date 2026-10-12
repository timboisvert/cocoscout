# frozen_string_literal: true

# Sends one notification to every phone a person has the app on, off the
# request thread (PushNotificationService queues it). Phones Apple says are
# gone (the app was deleted) are forgotten. Android comes with the Android
# app; its tokens are skipped until then.
class PushDeliveryJob < ApplicationJob
  queue_as :default

  # notification: { "title", "body", "data" (our own keys, like "path"), "badge" }
  def perform(user_id, notification)
    return unless ApnsClient.configured?

    user = User.find_by(id: user_id)
    return unless user

    payload = self.class.payload(notification)
    user.device_tokens.where(platform: "ios").group_by(&:apns_environment).each do |environment, devices|
      ApnsClient.open(environment) do |apns|
        devices.each { |device| deliver(apns, device, payload) }
      end
    end
  end

  def self.payload(notification)
    aps = { alert: { title: notification["title"], body: notification["body"] }.compact, sound: "default" }
    aps[:badge] = notification["badge"].to_i if notification["badge"]
    (notification["data"] || {}).merge(aps: aps)
  end

  private

  def deliver(apns, device, payload)
    result = apns.deliver(device.token, payload)
    return if result.ok?

    if result.gone?
      device.destroy
    else
      Rails.logger.warn("[PushDeliveryJob] APNs #{result.status} #{result.reason} for device token #{device.id}")
    end
  end
end

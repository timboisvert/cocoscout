# frozen_string_literal: true

# Sends one notification to every phone a person has the app on, off the
# request thread (PushNotificationService queues it): iPhones through Apple
# (ApnsClient), Android phones through Google (FcmClient). Phones either says
# are gone (the app was deleted) are forgotten.
class PushDeliveryJob < ApplicationJob
  queue_as :default

  # notification: { "title", "body", "data" (our own keys, like "path"), "badge" }
  def perform(user_id, notification)
    user = User.find_by(id: user_id)
    return unless user

    deliver_to_iphones(user, notification) if ApnsClient.configured?
    deliver_to_androids(user, notification) if FcmClient.configured?
  end

  def self.payload(notification)
    alert = { title: notification["title"], subtitle: notification["subtitle"], body: notification["body"] }.compact
    aps = { alert: alert, sound: "default" }
    aps[:badge] = notification["badge"].to_i if notification["badge"]
    (notification["data"] || {}).merge(aps: aps)
  end

  # Android gets data only, every value a string; the app shows it.
  def self.android_data(notification)
    shown = notification.slice("title", "subtitle", "body", "badge")
    (notification["data"] || {}).merge(shown).compact.transform_values(&:to_s)
  end

  private

  def deliver_to_iphones(user, notification)
    payload = self.class.payload(notification)
    user.device_tokens.where(platform: "ios").group_by(&:apns_environment).each do |environment, devices|
      ApnsClient.open(environment) do |apns|
        devices.each { |device| settle(device, apns.deliver(device.token, payload), "APNs") }
      end
    end
  end

  def deliver_to_androids(user, notification)
    devices = user.device_tokens.where(platform: "android").to_a
    return if devices.empty?

    data = self.class.android_data(notification)
    FcmClient.open do |fcm|
      devices.each { |device| settle(device, fcm.deliver(device.token, data), "FCM") }
    end
  end

  def settle(device, result, service)
    return if result.ok?

    if result.gone?
      device.destroy
    else
      Rails.logger.warn("[PushDeliveryJob] #{service} #{result.status} #{result.reason} for device token #{device.id}")
    end
  end
end

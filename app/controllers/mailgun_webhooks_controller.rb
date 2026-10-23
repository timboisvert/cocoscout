# frozen_string_literal: true

# What Mailgun saw happen to emails to followers (FOLLOWERS_MAIL_DOMAIN):
# delivered, bounced for good, marked as spam, or unsubscribed through
# Mailgun. A bounce or complaint goes on the platform-wide suppression list,
# so no organization on CocoScout emails that address again. Each event is
# handled once (WebhookEvent). Signed with MAILGUN_WEBHOOK_SIGNING_KEY.
class MailgunWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access

  PROVIDER = "mailgun"

  def create
    return head(:not_acceptable) unless valid_signature?

    data = event_data
    event_id = data["id"].to_s
    return head(:ok) unless WebhookEvent.claim!(provider: PROVIDER, event_id: event_id, event_type: data["event"])

    begin
      handle(data)
      WebhookEvent.finish!(provider: PROVIDER, event_id: event_id)
      head :ok
    rescue StandardError => e
      WebhookEvent.fail!(provider: PROVIDER, event_id: event_id, error: "#{e.class}: #{e.message}")
      raise
    end
  end

  private

  def event_data
    data = params.to_unsafe_h["event-data"]
    data.is_a?(Hash) ? data.deep_stringify_keys : {}
  end

  # Mailgun signs timestamp + token with the webhook signing key (HMAC SHA-256).
  def valid_signature?
    key = ENV["MAILGUN_WEBHOOK_SIGNING_KEY"].presence
    signature = params.to_unsafe_h["signature"]
    return false unless key && signature.is_a?(Hash)

    timestamp = signature["timestamp"].to_s
    token = signature["token"].to_s
    expected = OpenSSL::HMAC.hexdigest("SHA256", key, "#{timestamp}#{token}")
    fresh = (Time.current.to_i - timestamp.to_i).abs < 15.minutes.to_i
    fresh && ActiveSupport::SecurityUtils.secure_compare(expected, signature["signature"].to_s)
  end

  def handle(data)
    delivery = find_delivery(data)
    recipient = data["recipient"].to_s.strip.downcase
    case data["event"]
    when "delivered"
      delivery&.update!(status: "delivered", delivered_at: Time.current)
    when "failed"
      # Mailgun keeps trying a temporary failure; only a permanent one counts.
      return unless data["severity"] == "permanent"

      delivery&.update!(status: "bounced", failed_at: Time.current, error: data.dig("delivery-status", "message").to_s.first(500).presence)
      EmailSuppression.suppress!(recipient, reason: "bounced", source: "mailgun") if recipient.present?
      Follower.where(email: recipient, status: "subscribed").update_all(status: "bounced", updated_at: Time.current)
    when "complained"
      delivery&.update!(status: "complained")
      EmailSuppression.suppress!(recipient, reason: "complained", source: "mailgun") if recipient.present?
      Follower.where(email: recipient, status: "subscribed").update_all(status: "complained", updated_at: Time.current)
    when "unsubscribed"
      delivery&.follower&.unsubscribe!
    end
  end

  def find_delivery(data)
    id = data.dig("user-variables", "delivery_id").presence
    return FollowerEmailDelivery.find_by(id: id) if id

    message_id = data.dig("message", "headers", "message-id").to_s.delete("<>")
    message_id.present? ? FollowerEmailDelivery.find_by(mailgun_message_id: message_id) : nil
  end
end

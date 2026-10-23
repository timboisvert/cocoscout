# frozen_string_literal: true

# Sends an email's queued copies, one per follower, on the followers' own
# Mailgun domain (FollowerMailer). Safe to run again: it only sends what's
# still queued. Someone who unsubscribed or bounced after the send was
# confirmed is skipped. One organization's send at a time.
class FollowerEmailSendJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(follower_email_id) { "follower-email-#{FollowerEmail.find_by(id: follower_email_id)&.organization_id}" }

  def perform(follower_email_id)
    follower_email = FollowerEmail.find_by(id: follower_email_id)
    return unless follower_email && follower_email.status == "sending"

    follower_email.follower_email_deliveries.where(status: "queued").includes(:follower).find_each(batch_size: 200) do |delivery|
      send_one(delivery)
    end
    follower_email.update!(status: "sent") unless follower_email.follower_email_deliveries.where(status: "queued").exists?
  end

  private

  def send_one(delivery)
    follower = delivery.follower
    unless follower&.emailable?
      delivery.update!(status: "skipped")
      return
    end

    message = FollowerMailer.follower_email(delivery).deliver_now
    delivery.update!(status: "sent", sent_at: Time.current, mailgun_message_id: message&.message_id.to_s.delete("<>").presence)
    follower.update_column(:last_emailed_at, Time.current)
  rescue StandardError => e
    Rails.logger.error("[FollowerEmailSendJob] delivery #{delivery.id}: #{e.class} #{e.message}")
    delivery.update_columns(status: "failed", failed_at: Time.current, error: e.message.to_s.first(500), updated_at: Time.current)
  end
end

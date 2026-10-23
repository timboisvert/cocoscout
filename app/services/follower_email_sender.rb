# frozen_string_literal: true

# Sends an email to followers: one FollowerEmailDelivery per person it goes
# to (FollowerAudience), then FollowerEmailSendJob sends them. A send the
# manager confirmed goes to exactly who the send window counted.
class FollowerEmailSender
  class Error < StandardError; end

  def self.send!(follower_email, user)
    # Never on cocoscout.com's own domain in production: a bad list must not
    # touch sign-in and payment mail (FOLLOWERS_MAIL_DOMAIN, release checklist).
    raise Error, "Sending to followers isn't switched on yet." if Rails.env.production? && ENV["FOLLOWERS_MAIL_DOMAIN"].blank?
    raise Error, "This email was already sent." unless follower_email.draft?
    raise Error, "Add a subject first." if follower_email.subject.blank?
    raise Error, "Write something first." if follower_email.body.blank? && follower_email.show_ids.blank?

    recipients = follower_email.audience.recipients
    raise Error, "Nobody on those lists can be emailed." unless recipients.exists?

    now = Time.current
    follower_email.with_lock do
      raise Error, "This email was already sent." unless follower_email.draft?

      rows = recipients.pluck(:id, :email).map do |id, email|
        { follower_email_id: follower_email.id, follower_id: id, email: email, status: "queued", created_at: now, updated_at: now }
      end
      rows.each_slice(1000) { |slice| FollowerEmailDelivery.insert_all(slice, unique_by: :index_follower_email_deliveries_unique) }
      follower_email.update!(status: "sending", sent_at: now, sent_by: user, recipient_count: rows.size)
    end
    FollowerEmailSendJob.perform_later(follower_email.id)
    follower_email
  end
end

# frozen_string_literal: true

# Sends an email to followers: one FollowerEmailDelivery per person it goes
# to (FollowerAudience), then FollowerEmailSendJob sends them. A send the
# manager confirmed goes to exactly who the send window counted.
class FollowerEmailSender
  class Error < StandardError; end

  def self.switched_on?
    return true unless Rails.env.production?

    ENV["FOLLOWERS_MAIL_DOMAIN"].present? || ENV["FOLLOWERS_SENDING"] == "on"
  end

  # `buy_blocks`: how many blocks of extra emails the sender agreed to buy
  # for this send (FollowerEmailBlock). It must be exactly what the send
  # needs, as the send window showed it: nobody is charged for a number they
  # didn't see.
  def self.send!(follower_email, user, buy_blocks: 0)
    # In production only once it's switched on: its own sending domain
    # (FOLLOWERS_MAIL_DOMAIN, release checklist §2b), or, while we try it out,
    # cocoscout.com's own domain under a CocoScout-wide monthly cap
    # (FOLLOWERS_SENDING=on; Tim, 2026-10-28).
    raise Error, "Sending to followers isn't switched on yet." unless switched_on?
    raise Error, "This email was already sent." unless follower_email.draft?
    raise Error, "Add a subject first." if follower_email.subject.blank?
    raise Error, "Write something first." if follower_email.body.blank? && follower_email.show_ids.blank?

    recipients = follower_email.audience.recipients
    raise Error, "Nobody on those lists can be emailed." unless recipients.exists?

    allowance = FollowerEmailAllowance.new(follower_email.organization)
    count = recipients.count
    unless FollowerEmailAllowance.platform_allows?(count)
      raise Error, "CocoScout has sent all the emails to followers it can this month. Sending opens again on " \
                   "#{allowance.resets_on.strftime('%b %-d')}, or pick a smaller list or segment."
    end
    needed = allowance.blocks_needed(count)
    if needed.positive? && buy_blocks.to_i != needed
      raise Error, "This would send #{count} emails, and you have #{allowance.left_words}. " \
                   "Add #{ActiveSupport::NumberHelper.number_to_delimited(needed * FollowerEmailBlock::EMAILS)} more for #{ActiveSupport::NumberHelper.number_to_currency(needed * FollowerEmailBlock::PRICE_CENTS / 100.0, precision: 0)}, " \
                   "or pick a smaller list or segment."
    end
    paid = allowance.paid_part(count)

    now = Time.current
    follower_email.with_lock do
      raise Error, "This email was already sent." unless follower_email.draft?

      rows = recipients.pluck(:id, :email).map do |id, email|
        { follower_email_id: follower_email.id, follower_id: id, email: email, status: "queued", created_at: now, updated_at: now }
      end
      rows.each_slice(1000) { |slice| FollowerEmailDelivery.insert_all(slice, unique_by: :index_follower_email_deliveries_unique) }
      needed.times { follower_email.organization.follower_email_blocks.create!(bought_by: user, follower_email: follower_email) }
      follower_email.update!(status: "sending", sent_at: now, sent_by: user, recipient_count: rows.size, paid_emails_used: paid)
    end
    FollowerEmailSendJob.perform_later(follower_email.id)
    follower_email
  end
end

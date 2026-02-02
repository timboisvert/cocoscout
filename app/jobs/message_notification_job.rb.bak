class MessageDigestJob < ApplicationJob
  queue_as :default

  # Run this hourly via cron/recurring job
  def perform
    User.where(message_digest_enabled: true).find_each do |user|
      process_user(user)
    end
  end

  private

  def process_user(user)
    # Get unread messages older than 1 hour (grace period for in-app viewing)
    unread_messages = user.unread_messages
                          .where("messages.created_at < ?", 1.hour.ago)
                          .includes(:sender, :recipient, :regarding)
                          .order(created_at: :desc)

    # Skip if no unread messages (or all are within grace period)
    return if unread_messages.empty?

    # Skip if already sent digest in last 24 hours
    return if user.last_message_digest_sent_at&.> 24.hours.ago

    # Send digest with ALL unread messages
    MessageDigestMailer.unread_digest(
      user: user,
      messages: unread_messages.to_a
    ).deliver_later

    # Update timestamp to prevent spam
    user.update!(last_message_digest_sent_at: Time.current)
  end
end

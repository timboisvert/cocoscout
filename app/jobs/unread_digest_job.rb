# frozen_string_literal: true

# Sends digest emails to users who have unread messages and haven't
# checked their inbox recently.
#
# Adaptive throttle strategy:
# - Wait 4 hours after messages arrive before sending first digest; 2 days for
#   someone with push notifications on (User#push_enabled?), who heard about
#   it at once, so the email only catches what's still unread (Tim,
#   2026-10-12; lengthened 2026-10-28 now that the apps are out: fewer emails)
# - Start with 1 day throttle (baseline frequency)
# - If user checks inbox after digest: reset to 1 day (they're engaged)
# - If user ignores digest: double the throttle (1 → 2 → 4 → 8 → 14 days max)
# - Only send if user actually has unread messages
#
# Run this job every 15 minutes via cron/recurring schedule
class UnreadDigestJob < ApplicationJob
  queue_as :default

  # How long to wait before sending first digest after new message
  INITIAL_DELAY = 4.hours
  INITIAL_DELAY_WITH_PUSH = 2.days

  # Maximum throttle period for unresponsive users
  MAX_THROTTLE_DAYS = 14

  def perform
    users_needing_digest.find_each do |user|
      send_digest_to(user)
    end
  end

  private

  def users_needing_digest
    # Users who:
    # 1. Have message digests enabled
    # 2. Have at least one unread message subscription (using counter cache)
    # 3. Haven't received a digest email in their current throttle period (or never)

    # 4. (V1.1) Or have an unread notification the digest still owes an
    #    email: a notice that was a message before it became a Notification.
    with_unread = MessageSubscription.where("unread_count > 0").select(:user_id)
    owed = Notification.owed_a_digest.select(:user_id)
    User
      .where(message_digest_enabled: true)
      .where("users.id IN (#{with_unread.to_sql}) OR users.id IN (#{owed.to_sql})")
      .where(
        "users.last_unread_digest_sent_at IS NULL OR " \
        "users.last_unread_digest_sent_at < NOW() - (users.digest_throttle_days || ' days')::interval"
      )
  end

  def send_digest_to(user)
    unread_threads = collect_unread_threads(user)
    notifications = user.notifications.owed_a_digest.order(:created_at).to_a
    return if unread_threads.empty? && notifications.empty?

    # Check if the oldest unread is old enough (waited INITIAL_DELAY)
    oldest_unread_at = [ find_oldest_unread_at(user, unread_threads), notifications.first&.created_at ].compact.min
    delay = user.push_enabled? ? INITIAL_DELAY_WITH_PUSH : INITIAL_DELAY
    return if oldest_unread_at.nil? || oldest_unread_at > delay.ago

    # Adjust throttle based on whether user checked inbox after last digest
    adjust_throttle(user)

    # Send the digest
    MessageNotificationMailer.unread_digest(user: user, unread_threads: unread_threads, notifications: notifications).deliver_later

    # Update tracking
    user.update!(last_unread_digest_sent_at: Time.current)
    Notification.where(id: notifications.map(&:id)).update_all(digested_at: Time.current) if notifications.any?

    Rails.logger.info "[UnreadDigestJob] Sent digest to #{user.email_address} with #{unread_threads.size} threads (throttle: #{user.digest_throttle_days} days)"
  end

  def adjust_throttle(user)
    # If this is the first digest ever, keep baseline
    return if user.last_unread_digest_sent_at.nil?

    # Check if user visited inbox since last digest was sent
    if user.last_inbox_visit_at.present? && user.last_inbox_visit_at > user.last_unread_digest_sent_at
      # User is engaged - reset to baseline frequency
      user.update!(digest_throttle_days: 1)
    else
      # User didn't check - back off by doubling, up to max
      new_throttle = [ user.digest_throttle_days * 2, MAX_THROTTLE_DAYS ].min
      user.update!(digest_throttle_days: new_throttle)
    end
  end

  def collect_unread_threads(user)
    user.message_subscriptions.unread.includes(message: :production).filter_map do |subscription|
      root_message = subscription.message

      # In-app-only messages (e.g. agreement requests) never go in the digest.
      next if root_message.skip_digest?

      # Use the counter cache for unread count
      unread_count = subscription.unread_count
      next if unread_count == 0

      { message: root_message, unread_count: unread_count }
    end
  end

  def find_oldest_unread_at(user, unread_threads)
    oldest = nil

    unread_threads.each do |thread|
      subscription = user.message_subscriptions.find_by(message: thread[:message])
      next unless subscription

      if subscription.last_read_at.nil?
        # Never read - use root message creation time
        candidate = thread[:message].created_at
      else
        # Find oldest message after last_read_at
        candidate = Message
          .where(id: [ thread[:message].id ] + thread[:message].descendant_ids)
          .where("created_at > ?", subscription.last_read_at)
          .minimum(:created_at)
      end

      oldest = candidate if candidate && (oldest.nil? || candidate < oldest)
    end

    oldest
  end
end

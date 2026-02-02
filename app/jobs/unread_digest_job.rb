# frozen_string_literal: true

# Sends digest emails to users who have unread messages and haven't
# checked their inbox recently.
#
# Strategy:
# - Wait 1 hour after messages arrive before sending digest
# - If user hasn't visited inbox since the message arrived, send digest
# - Don't send another digest for 3 days, even if new messages arrive
# - Only send if user actually has unread messages
#
# Run this job every 15 minutes via cron/recurring schedule
class UnreadDigestJob < ApplicationJob
  queue_as :default

  # How long to wait before sending first digest after new message
  INITIAL_DELAY = 1.hour

  # How long to wait before sending another digest after the last one
  THROTTLE_PERIOD = 3.days

  def perform
    users_needing_digest.find_each do |user|
      send_digest_to(user)
    end
  end

  private

  def users_needing_digest
    # Users who:
    # 1. Have at least one unread message subscription
    # 2. Haven't visited their inbox since the oldest unread message
    # 3. Haven't received a digest email in the throttle period (or never)
    # 4. The oldest unread message is older than INITIAL_DELAY

    User
      .joins(:message_subscriptions)
      .where(message_subscriptions: { last_read_at: nil })
      .or(
        User.joins(:message_subscriptions)
          .joins("INNER JOIN messages ON messages.id = message_subscriptions.message_id")
          .where("messages.updated_at > message_subscriptions.last_read_at")
      )
      .where("users.last_unread_digest_sent_at IS NULL OR users.last_unread_digest_sent_at < ?", THROTTLE_PERIOD.ago)
      .distinct
  end

  def send_digest_to(user)
    unread_threads = collect_unread_threads(user)
    return if unread_threads.empty?

    # Check if the oldest unread is old enough (waited INITIAL_DELAY)
    oldest_unread_at = find_oldest_unread_at(user, unread_threads)
    return if oldest_unread_at.nil? || oldest_unread_at > INITIAL_DELAY.ago

    # Check if user visited inbox after the oldest unread - if so, skip
    if user.last_inbox_visit_at.present? && user.last_inbox_visit_at > oldest_unread_at
      return
    end

    # Send the digest
    MessageNotificationMailer.unread_digest(user: user, unread_threads: unread_threads).deliver_later

    # Update tracking
    user.update!(last_unread_digest_sent_at: Time.current)

    Rails.logger.info "[UnreadDigestJob] Sent digest to #{user.email_address} with #{unread_threads.size} threads"
  end

  def collect_unread_threads(user)
    user.message_subscriptions.includes(message: :production).filter_map do |subscription|
      next unless subscription.unread?

      root_message = subscription.message
      unread_count = count_unread_in_thread(root_message, subscription.last_read_at)

      next if unread_count == 0

      { message: root_message, unread_count: unread_count }
    end
  end

  def count_unread_in_thread(root_message, last_read_at)
    if last_read_at.nil?
      # Never read - count all messages in thread
      1 + root_message.descendant_ids.count
    else
      # Count messages newer than last_read_at
      Message.where(id: [ root_message.id ] + root_message.descendant_ids)
             .where("created_at > ?", last_read_at)
             .count
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

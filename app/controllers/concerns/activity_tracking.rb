# frozen_string_literal: true

# Tracks when users are active in the application by updating their User's
# last_seen_at timestamp via a background job. Uses a cookie-based throttle
# to avoid queuing a job on every single request.
module ActivityTracking
  extend ActiveSupport::Concern

  included do
    after_action :track_activity, if: :should_track_activity?
  end

  private

  # Only track if there's a current user
  def should_track_activity?
    Current.user.present?
  end

  def track_activity
    user = Current.user

    # Throttle: only update every 15 minutes per user
    # Use a cookie to avoid hitting the database to check last_seen_at
    throttle_key = "last_seen_#{user.id}"
    last_tracked = cookies.signed[throttle_key]

    # If we tracked within the last 15 minutes, skip
    return if last_tracked.present? && Time.zone.parse(last_tracked) > 15.minutes.ago

    # Set cookie for throttling (expires in 15 minutes)
    cookies.signed[throttle_key] = {
      value: Time.current.iso8601,
      expires: 15.minutes.from_now,
      httponly: true
    }

    # Queue the background job to update last_seen_at
    UpdateLastSeenJob.perform_later(user.id)
  end
end

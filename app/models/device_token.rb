# frozen_string_literal: true

# A phone that gets push notifications. The iOS app files its token under the
# web sign-in it runs on (session), so signing out ends the notifications;
# API sign-ins file theirs under an app_session. The app checks in each time
# it opens (updated_at), and a phone quiet for a month no longer counts.
class DeviceToken < ApplicationRecord
  STALE_AFTER = 30.days

  belongs_to :user
  belongs_to :session, optional: true
  belongs_to :app_session, optional: true

  validates :token, presence: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
  validates :token, uniqueness: { scope: :platform }
  validates :apns_environment, inclusion: { in: %w[production sandbox] }

  scope :recent, -> { where("device_tokens.updated_at > ?", STALE_AFTER.ago) }
end

# frozen_string_literal: true

# One person's day in the iPhone or Android app: which platform, and which
# build (app_version nil is a V1 build, which says no version). Written once a
# day per person by AppUsageTracking; read by AppUsageReport.
class AppActivityDay < ApplicationRecord
  PLATFORMS = %w[ios android].freeze

  belongs_to :user

  validates :platform, inclusion: { in: PLATFORMS }

  # Today's row for this person, or the one already there.
  def self.record!(user, platform:, app_version:, nav:, day: Date.current)
    upsert({ user_id: user.id, day: day, platform: platform, app_version: app_version, nav: nav,
             created_at: Time.current, updated_at: Time.current },
           unique_by: %i[user_id day], on_duplicate: :skip)
  end
end

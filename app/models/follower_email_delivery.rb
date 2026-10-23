# frozen_string_literal: true

# One follower's copy of an email: what Mailgun said happened to it.
class FollowerEmailDelivery < ApplicationRecord
  STATUSES = %w[queued sent delivered bounced complained failed skipped].freeze

  belongs_to :follower_email
  belongs_to :follower

  validates :status, inclusion: { in: STATUSES }

  scope :sent_since, ->(time) { where(sent_at: time..) }
end

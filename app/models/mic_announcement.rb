# frozen_string_literal: true

# A producer-posted news item on a mic. Optionally fans out to
# `MicSignupAlert` subscribers via email.
class MicAnnouncement < ApplicationRecord
  belongs_to :mic
  belongs_to :posted_by, class_name: "User", foreign_key: :posted_by_user_id

  validates :body, presence: true, length: { maximum: 4_000 }
  validates :posted_at, presence: true

  scope :recent, ->(limit = 5) { order(posted_at: :desc).limit(limit) }
end

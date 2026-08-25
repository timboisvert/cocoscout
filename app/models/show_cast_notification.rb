# frozen_string_literal: true

class ShowCastNotification < ApplicationRecord
  belongs_to :show
  belongs_to :assignable, polymorphic: true
  # Optional: the role nullifies when an act is cut from the running order,
  # keeping the person-level record that they were notified.
  belongs_to :role, optional: true

  enum :notification_type, { cast: 0, removed: 1 }

  validates :notified_at, presence: true
  validates :notification_type, presence: true

  scope :for_show, ->(show) { where(show: show) }
  scope :cast_notifications, -> { where(notification_type: :cast) }
end

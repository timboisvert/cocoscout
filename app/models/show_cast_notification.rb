# frozen_string_literal: true

class ShowCastNotification < ApplicationRecord
  belongs_to :show
  belongs_to :assignable, polymorphic: true
  belongs_to :role

  enum :notification_type, { cast: 0, removed: 1 }

  validates :notified_at, presence: true
  validates :notification_type, presence: true

  scope :for_show, ->(show) { where(show: show) }
  scope :cast_notifications, -> { where(notification_type: :cast) }
  scope :removed_notifications, -> { where(notification_type: :removed) }

  # Get the unique assignables that were previously notified as cast for this show
  def self.previously_cast_assignables(show)
    cast_notifications
      .for_show(show)
      .select(:assignable_type, :assignable_id)
      .distinct
      .map(&:assignable)
  end
end

class GroupMembership < ApplicationRecord
  belongs_to :group
  belongs_to :person

  # Permission levels: view, write, owner
  enum :permission_level, {
    view: 0,
    write: 1,
    owner: 2
  }, default: :view

  validates :group, presence: true
  validates :person, presence: true
  validates :person_id, uniqueness: { scope: :group_id, message: "is already a member of this group" }

  # Notification preferences stored as JSON
  serialize :notification_preferences, coder: JSON

  def notifications_enabled?
    return true if owner? # Owners always receive notifications
    notification_preferences&.dig("enabled") != false
  end

  def enable_notifications!
    self.notification_preferences = { "enabled" => true }
    save
  end

  def disable_notifications!
    return false if owner? # Cannot disable for owners
    self.notification_preferences = { "enabled" => false }
    save
  end
end

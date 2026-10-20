# frozen_string_literal: true

# One automated event for one person (V1.1 plan §9): "Dan signed the contract",
# "Your pay is on its way", "A ticket sold". It reaches them by push and email
# as their settings say (NotificationGroups), and always shows in their
# Notifications list, read or not. Messages are people talking to people.
#
# category is the NotificationGroups key; kind is what happened within it.
# path is where a tap goes; reply_path, when set, opens a real thread with the
# team (the notice itself is never the thread). Copy comes from the event's
# ContentTemplate (Notifier), never from here.
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :organization, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, :category, :title, presence: true
  validates :category, inclusion: { in: ->(_) { NotificationGroups.keys } }

  scope :unread, -> { where(read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :in_category, ->(keys) { where(category: Array(keys)) }
  # Unread notices the unread digest still owes an email (UnreadDigestJob).
  scope :owed_a_digest, -> { unread.where(digest: true, digested_at: nil) }

  def read? = read_at.present?

  def group = NotificationGroups.find(category)

  # Its page lives in production mode, so opening it from My asks first.
  def production_mode? = path.to_s.start_with?("/manage")

  def mark_read!
    update_column(:read_at, Time.current) unless read?
  end
end

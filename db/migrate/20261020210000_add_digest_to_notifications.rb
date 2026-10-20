# frozen_string_literal: true

# A notice that moved from Messages to Notifications kept its email through
# the unread digest (UnreadDigestJob): digest marks the ones the digest
# still owes an email, digested_at when it sent it.
class AddDigestToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :digest, :boolean, default: false, null: false
    add_column :notifications, :digested_at, :datetime
    add_index :notifications, %i[user_id digest digested_at], where: "read_at IS NULL", name: "index_notifications_owed_a_digest"
  end
end

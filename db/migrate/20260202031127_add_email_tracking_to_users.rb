class AddEmailTrackingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_unread_digest_sent_at, :datetime
    add_column :users, :last_inbox_visit_at, :datetime
  end
end

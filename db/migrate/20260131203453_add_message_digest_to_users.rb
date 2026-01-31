class AddMessageDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :message_digest_enabled, :boolean, default: true
    add_column :users, :last_message_digest_sent_at, :datetime, null: true
  end
end

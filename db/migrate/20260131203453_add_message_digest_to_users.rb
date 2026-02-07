class AddMessageDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :message_digest_enabled, :boolean, default: true
    add_column :users, :last_message_digest_sent_at, :datetime, null: true

    # Backfill existing users to have digest enabled
    reversible do |dir|
      dir.up do
        User.where(message_digest_enabled: nil).update_all(message_digest_enabled: true)
      end
    end
  end
end

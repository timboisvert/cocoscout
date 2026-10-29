# frozen_string_literal: true

# Mailing lists stay, with their followers and the emails a Pro organization
# sends them; sharing a list with an outside producer (My Followers) is gone
# (Tim, 2026-10-28).
class RemoveMailingListSharing < ActiveRecord::Migration[8.1]
  def up
    drop_table :mailing_list_shares
    execute "DELETE FROM content_templates WHERE key = 'follower_share_invitation'"
  end

  def down
    create_table :mailing_list_shares do |t|
      t.references :mailing_list, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :granted_by, foreign_key: { to_table: :users }
      t.datetime :granted_at, null: false
      t.timestamps
    end
    add_index :mailing_list_shares, %i[mailing_list_id person_id], unique: true
  end
end

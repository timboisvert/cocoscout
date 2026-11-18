# frozen_string_literal: true

# The unread digest stops after three in a row that were ignored, until the
# person comes back (Tim, 2026-11-09: fewer emails; a third of a month's
# digests went to people who hadn't been on the site in thirty days). The
# count starts from what the doubling throttle already says: it doubled once
# for each digest that was ignored.
class AddDigestsIgnoredToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :digests_ignored, :integer, null: false, default: 0
    execute <<~SQL.squish
      UPDATE users
         SET digests_ignored = CASE WHEN digest_throttle_days >= 8 THEN 3 WHEN digest_throttle_days >= 4 THEN 2 WHEN digest_throttle_days >= 2 THEN 1 ELSE 0 END
       WHERE last_unread_digest_sent_at IS NOT NULL AND digest_throttle_days > 1
    SQL
  end

  def down
    remove_column :users, :digests_ignored
  end
end

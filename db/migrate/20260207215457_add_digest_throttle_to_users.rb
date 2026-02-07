class AddDigestThrottleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :digest_throttle_days, :integer, default: 1, null: false

    reversible do |dir|
      dir.up do
        # Set existing users to baseline throttle
        User.where(digest_throttle_days: nil).update_all(digest_throttle_days: 1)
      end
    end
  end
end

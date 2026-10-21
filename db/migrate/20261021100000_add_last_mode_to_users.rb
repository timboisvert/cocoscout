# frozen_string_literal: true

# The mode a person last used, on their account (V1.1 plan §8: the cookie
# alone forgets on a new phone, so the app opened on My for someone who lives
# in production mode). Written only on real page loads, and only when it
# changes.
class AddLastModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_mode, :string
  end
end

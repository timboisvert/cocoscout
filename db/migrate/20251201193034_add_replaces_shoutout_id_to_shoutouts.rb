# frozen_string_literal: true

class AddReplacesShoutoutIdToShoutouts < ActiveRecord::Migration[8.1]
  def change
    add_column :shoutouts, :replaces_shoutout_id, :integer
    add_index :shoutouts, :replaces_shoutout_id
  end
end

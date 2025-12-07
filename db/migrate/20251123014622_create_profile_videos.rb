# frozen_string_literal: true

class CreateProfileVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_videos do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :title, limit: 100
      t.string :url, null: false
      t.integer :video_type, default: 2, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :profile_videos, %i[profileable_type profileable_id position]
  end
end

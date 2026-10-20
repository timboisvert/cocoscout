# frozen_string_literal: true

# Notifications, separate from Messages (V1.1 plan §9): one row per person per
# automated event, with a link to what it's about. Messages become people
# talking to people.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, foreign_key: true
      t.string :kind, null: false
      t.string :category, null: false
      t.string :title, null: false
      t.text :body
      t.string :path
      t.string :reply_path
      t.references :subject, polymorphic: true
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, %i[user_id created_at]
    add_index :notifications, %i[user_id read_at]
  end
end

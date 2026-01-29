# frozen_string_literal: true

class AddSmsSupport < ActiveRecord::Migration[8.0]
  def change
    # Add dismissed announcements tracking to users
    add_column :users, :dismissed_announcements, :jsonb, default: [], null: false

    # Create SMS logs table for tracking all sent messages
    create_table :sms_logs do |t|
      t.references :user, foreign_key: true, null: true
      t.string :phone, null: false
      t.text :message, null: false
      t.string :sms_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :sns_message_id
      t.text :error_message
      t.datetime :sent_at
      t.references :organization, foreign_key: true, null: true
      t.references :production, foreign_key: true, null: true

      t.timestamps
    end

    add_index :sms_logs, :phone
    add_index :sms_logs, :sms_type
    add_index :sms_logs, :status
    add_index :sms_logs, :sent_at
  end
end

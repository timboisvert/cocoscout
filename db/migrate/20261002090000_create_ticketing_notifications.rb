# frozen_string_literal: true

# Who at a theater gets which Ticketing emails (Ticketing settings →
# Notifications), and a log so once-only notices — a show selling out, a
# day's summary — are only ever sent once.
class CreateTicketingNotifications < ActiveRecord::Migration[8.1]
  def change
    # Extra addresses (a box office inbox) beside the managers.
    add_column :ticketing_profiles, :notification_emails, :jsonb, null: false, default: []
    # kind => ["user:12", "email:box@x.com"]; empty until the theater saves its own.
    add_column :ticketing_profiles, :notification_rules, :jsonb, null: false, default: {}

    create_table :ticketing_notification_logs do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :about_type, null: false, default: ""
      t.bigint :about_id, null: false, default: 0
      t.string :occasion, null: false, default: ""
      t.datetime :created_at, null: false
    end
    add_index :ticketing_notification_logs, %i[organization_id kind about_type about_id occasion],
              unique: true, name: "index_ticketing_notification_logs_once"
  end
end

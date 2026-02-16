# frozen_string_literal: true

class CreateWebhookLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_logs do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :ticket_listing, null: true, foreign_key: true

      t.string :event_type, null: false
      t.string :external_id
      t.jsonb :payload, null: false, default: {}
      t.jsonb :headers, default: {}

      t.string :status, null: false, default: "received"
      t.string :processing_error
      t.datetime :processed_at

      t.string :ip_address
      t.string :signature_status

      t.timestamps
    end

    add_index :webhook_logs, :event_type
    add_index :webhook_logs, :status
    add_index :webhook_logs, :external_id
    add_index :webhook_logs, :created_at
    add_index :webhook_logs, [ :ticketing_provider_id, :external_id ], unique: true,
              name: "idx_webhook_logs_provider_external_id"
  end
end

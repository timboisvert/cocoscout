class CreateTicketingSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_sync_logs do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :ticketing_production_link, foreign_key: true
      t.references :user, foreign_key: true

      t.string :sync_type, null: false
      t.string :status, null: false

      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_failed, default: 0

      t.jsonb :details, default: {}
      t.text :error_message
      t.text :error_backtrace

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ticketing_sync_logs, [:ticketing_provider_id, :created_at],
              name: "idx_ticketing_sync_logs_provider_created"
    add_index :ticketing_sync_logs, :status
  end
end

class CreateTicketingProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_providers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :provider_type, null: false
      t.string :name, null: false

      # OAuth/API credentials (encrypted at application level)
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :token_expires_at
      t.text :api_key_ciphertext

      # Provider account info
      t.string :provider_account_id
      t.string :provider_account_name

      # Sync configuration
      t.boolean :auto_sync_enabled, default: true
      t.integer :sync_interval_minutes, default: 15

      # Status tracking
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error
      t.integer :consecutive_failures, default: 0

      t.timestamps
    end

    add_index :ticketing_providers, %i[organization_id provider_type]
    add_index :ticketing_providers, :provider_account_id
  end
end

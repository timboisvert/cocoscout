# frozen_string_literal: true

class EnhanceTicketingProviderCapabilities < ActiveRecord::Migration[8.0]
  def change
    # Provider capability and health tracking
    add_column :ticketing_providers, :manual_only, :boolean, default: false, null: false
    add_column :ticketing_providers, :capabilities, :jsonb, default: {}, null: false

    # Credential health tracking
    add_column :ticketing_providers, :credentials_valid, :boolean, default: true, null: false
    add_column :ticketing_providers, :credentials_checked_at, :datetime
    add_column :ticketing_providers, :credentials_expires_at, :datetime
    add_column :ticketing_providers, :credentials_error, :string

    # Rate limiting tracking
    add_column :ticketing_providers, :rate_limit_remaining, :integer
    add_column :ticketing_providers, :rate_limit_resets_at, :datetime
    add_column :ticketing_providers, :rate_limited_until, :datetime

    # Webhook configuration
    add_column :ticketing_providers, :webhook_endpoint_token, :string
    add_column :ticketing_providers, :webhook_enabled, :boolean, default: false, null: false
    add_column :ticketing_providers, :webhook_registered_at, :datetime

    add_index :ticketing_providers, :webhook_endpoint_token, unique: true
    add_index :ticketing_providers, :credentials_valid
  end
end

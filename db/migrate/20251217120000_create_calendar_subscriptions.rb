# frozen_string_literal: true

class CreateCalendarSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_subscriptions do |t|
      # Who owns this subscription
      t.references :person, null: false, foreign_key: true

      # Provider: google, outlook, or ical
      t.string :provider, null: false

      # OAuth tokens (encrypted)
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :token_expires_at

      # For iCal: unique token for the feed URL
      t.string :ical_token

      # Provider-specific calendar ID (for Google/Outlook, where events are created)
      t.string :calendar_id

      # Email address used for this calendar (for verification)
      t.string :email

      # Subscription preferences
      t.string :sync_scope, null: false, default: "assigned"
      # assigned = only shows where person/their groups are assigned
      # talent_pool = all shows for productions they're in the talent pool of

      # Which entities to sync for (stored as JSON array of {type: "Person"/"Group", id: N})
      t.json :sync_entities, default: []

      # Sync status
      t.boolean :enabled, null: false, default: true
      t.datetime :last_synced_at
      t.text :last_sync_error

      t.timestamps
    end

    add_index :calendar_subscriptions, [ :person_id, :provider ], unique: true
    add_index :calendar_subscriptions, :ical_token, unique: true

    # Track which calendar events we've created so we can update/delete them
    create_table :calendar_events do |t|
      t.references :calendar_subscription, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true

      # Provider-specific event ID
      t.string :provider_event_id, null: false

      # Last sync info
      t.datetime :last_synced_at
      t.string :last_sync_hash # Hash of event data to detect changes

      t.timestamps
    end

    add_index :calendar_events, [ :calendar_subscription_id, :show_id ], unique: true
    add_index :calendar_events, :provider_event_id
  end
end

# frozen_string_literal: true

# The calendar sync feature was removed in the dead-code sweep. Both tables were
# empty in production when it shipped (0 subscriptions, 0 events), and every
# model, service, job and controller that touched them is already gone, so
# nothing can reference these by the time this runs.
class DropCalendarSyncTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :calendar_events
    drop_table :calendar_subscriptions
  end

  def down
    create_table :calendar_subscriptions do |t|
      t.references :person, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :calendar_id
      t.string :email
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :token_expires_at
      t.string :ical_token
      t.boolean :enabled, default: true, null: false
      t.string :sync_scope, default: "assigned", null: false
      t.json :sync_entities, default: []
      t.datetime :last_synced_at
      t.text :last_sync_error
      t.timestamps
    end
    add_index :calendar_subscriptions, :ical_token, unique: true
    add_index :calendar_subscriptions, %i[person_id provider], unique: true

    create_table :calendar_events do |t|
      t.references :calendar_subscription, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.string :provider_event_id, null: false
      t.datetime :last_synced_at
      t.string :last_sync_hash
      t.timestamps
    end
    add_index :calendar_events, :provider_event_id
    add_index :calendar_events, %i[calendar_subscription_id show_id], unique: true
  end
end

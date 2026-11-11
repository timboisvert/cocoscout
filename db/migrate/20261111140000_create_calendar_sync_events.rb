# frozen_string_literal: true

# What the Google Calendar integration has put on the organization's
# calendar: one row per show or rental, with Google's id for its event and a
# digest of what was last written, so an unchanged date costs no call.
class CreateCalendarSyncEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_sync_events do |t|
      t.references :integration, null: false, foreign_key: true
      t.string :syncable_type, null: false
      t.bigint :syncable_id, null: false
      t.string :external_id, null: false
      t.string :digest, null: false
      t.datetime :synced_at, null: false
      t.timestamps
      t.index %i[integration_id syncable_type syncable_id], unique: true, name: "index_calendar_sync_events_on_what"
    end
  end
end

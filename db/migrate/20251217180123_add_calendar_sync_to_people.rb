# frozen_string_literal: true

class AddCalendarSyncToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :calendar_sync_enabled, :boolean, default: false, null: false
    add_column :people, :calendar_sync_scope, :string, default: "assignments_only"
    add_column :people, :calendar_sync_entities, :jsonb, default: {}
    add_column :people, :calendar_sync_email_confirmed, :boolean, default: false, null: false
  end
end

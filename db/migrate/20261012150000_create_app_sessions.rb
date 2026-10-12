# frozen_string_literal: true

# App sign-ins become device sessions that can be ended (Tim, 2026-10-12).
# The old API tokens couldn't be revoked: they lasted 30 days through sign-out
# and password changes. A device's push token belongs to its session, so
# ending the session stops its notifications too.
class CreateAppSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :app_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :device_name
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_used_at, null: false
      t.timestamps
    end
    add_index :app_sessions, :token_digest, unique: true

    add_reference :device_tokens, :app_session, foreign_key: { on_delete: :cascade }, index: true
  end
end

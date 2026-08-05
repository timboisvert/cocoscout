# frozen_string_literal: true

# Impersonation used to be tracked only in the Rails session and a signed
# cookie, both of which are browser-session cookies — while the login itself
# rides a *permanent* signed :session_id cookie. Mobile browsers drop session
# cookies aggressively (force-quit, tab eviction, memory pressure), so a
# superadmin stayed signed in as the impersonated person while the banner and
# its Stop button vanished. Pinning the impersonator to the Session record
# makes the banner exactly as durable as the login it belongs to.
class AddImpersonatorUserIdToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :impersonator_user_id, :bigint
    add_index :sessions, :impersonator_user_id
  end
end

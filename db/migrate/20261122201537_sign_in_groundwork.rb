# frozen_string_literal: true

# Groundwork for the sign-in plan (Tim, 2026-11-22): one screen that starts
# with the email address, 6-digit codes, and later Apple, Google, and passkeys.
#
#   user_identities   an Apple or Google account connected to a CocoScout
#                     account: one more key to the same account, never an
#                     account of its own.
#   sign_in_codes     the 6-digit codes we email. Only a digest is kept.
#   users.email_verified_at  when the person last proved they receive mail at
#                     their address (a code, a reset or invitation link, a
#                     provider). Nobody has proved it before today, so it
#                     starts empty for everyone.
#   users.password_set_at    when the person chose their password. It decides
#                     which step the sign-in screen shows (password or code),
#                     never what is safe. The backfill is a best guess: someone
#                     who has been seen signed in has chosen one.
#   sessions.sign_in_method  how this device got in (password, code, reset
#                     link, invitation, and later apple, google, passkey).
class SignInGroundwork < ActiveRecord::Migration[8.1]
  def up
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.boolean :private_email, null: false, default: false
      t.text :refresh_token
      t.string :client_id
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :user_identities, %i[provider uid], unique: true

    create_table :sign_in_codes do |t|
      t.string :email, null: false
      t.references :user, foreign_key: true
      t.string :purpose, null: false
      t.string :code_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.string :ip_address
      t.timestamps
    end
    add_index :sign_in_codes, %i[email purpose created_at]

    add_column :users, :email_verified_at, :datetime
    add_column :users, :password_set_at, :datetime
    add_column :sessions, :sign_in_method, :string

    execute "UPDATE users SET password_set_at = created_at WHERE last_seen_at IS NOT NULL"

    PlatformTemplates.ensure!(keys: %w[auth_sign_in_code])
  end

  def down
    ContentTemplate.where(key: "auth_sign_in_code").destroy_all
    remove_column :sessions, :sign_in_method
    remove_column :users, :password_set_at
    remove_column :users, :email_verified_at
    drop_table :sign_in_codes
    drop_table :user_identities
  end
end

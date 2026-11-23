# frozen_string_literal: true

# Passkeys (sign-in plan phase 4): one more key to the same account, like a
# connected Apple or Google account. A passkey is a key pair the person's
# phone, computer, or password manager made for cocoscout.com; we keep only
# its public half. `external_id` is the credential id the browser or app sends
# back when signing in (base64url), `public_key` the COSE key (base64url),
# `sign_count` the authenticator's counter, and `name` what the Account page
# calls it ("iCloud Keychain", "Google Password Manager").
#
# users.webauthn_id is the account's WebAuthn user handle: random, so a
# passkey never carries the account's database id.
class CreatePasskeys < ActiveRecord::Migration[8.1]
  def change
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :name
      t.string :transports, array: true, null: false, default: []
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true

    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true
  end
end

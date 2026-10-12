# frozen_string_literal: true

# The iOS app signs in through the website, so a phone's push token belongs
# to that web sign-in: signing out, or Sign out on the Account page, ends its
# notifications too. apns_environment says which Apple server the token
# belongs to (development builds use the sandbox).
class AddSessionToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :device_tokens, :session, foreign_key: { on_delete: :cascade }, index: true
    add_column :device_tokens, :apns_environment, :string, null: false, default: "production"
  end
end

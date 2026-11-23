# frozen_string_literal: true

# A passkey: one more key to the same account (sign-in plan phase 4), made by
# the person's phone, computer, or password manager for cocoscout.com while
# they were signed in. We keep only its public half; their face, fingerprint,
# or screen lock unlocks the private half on their device. SignIn::Passkeys
# makes and checks them.
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true

  # What the Account page shows for it.
  def shown_name
    name.presence || "Passkey"
  end
end

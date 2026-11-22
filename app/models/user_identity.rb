# frozen_string_literal: true

# An Apple or Google account connected to a CocoScout account: one more key
# to the same account, never an account of its own. `uid` is the provider's
# own subject id, which never changes; `email` is what the provider reported
# when it was connected, kept for the Account page. An Apple relay address
# (`private_email`) lives only here: the account's own email is always a real
# address, because invitations, contracts, and ticket orders find people by it.
class UserIdentity < ApplicationRecord
  PROVIDERS = %w[apple google].freeze

  belongs_to :user

  encrypts :refresh_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }

  def provider_name
    provider.capitalize
  end
end

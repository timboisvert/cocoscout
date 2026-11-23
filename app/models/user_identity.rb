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

  # Apple requires a disconnected Sign in with Apple to be revoked, and an
  # account's deletion to revoke it too (Apple's notifications that say it's
  # already gone set skip_revoke).
  attr_accessor :skip_revoke

  after_destroy_commit :revoke_with_apple, if: -> { provider == "apple" && refresh_token.present? && !skip_revoke }

  def provider_name
    SignIn::Providers.name(provider)
  end

  # What the Account page shows for it.
  def shown_email
    private_email ? "a private #{provider_name} address" : email.presence || "your #{provider_name} account"
  end

  private

  def revoke_with_apple
    SignIn::OAuth.revoke_apple(refresh_token, client_id: client_id)
  end
end

# frozen_string_literal: true

# Invitation pages sent to one email address (a team, the door, ticket sales).
# The invited address may already have an account. Its owner proves it's
# theirs with the account's password, or by already being signed in to it:
# the page offers "Sign in with a code", which goes through the sign-in screen
# and comes straight back, so someone who never chose a password (or forgot
# it) is not stuck.
module InvitationSignIn
  extend ActiveSupport::Concern

  included do
    helper_method :signed_in_as?, :code_way_in_link
  end

  private

  # Already signed in to this very account (allow_unauthenticated_access
  # pages don't resume the session on their own; authenticated? does).
  def signed_in_as?(user)
    user.present? && authenticated? && Current.user == user
  end

  def proved_invited_account?(user)
    signed_in_as?(user) || user.authenticate(params[:password].to_s).present?
  end

  # The sign-in screen, starting at this address, coming back to `return_to`.
  # Not named ..._path: CI checks every *_path a view calls against the routes.
  def code_way_in_link(email, return_to:)
    signin_path(start_over: 1, email_address: email, redirect_to: return_to)
  end

  # Signs the invited person in once they've accepted. Someone already signed
  # in to this account keeps the session they have.
  def start_invited_session(user, new_account:)
    return if signed_in_as?(user)

    start_new_session_for(user, sign_in_method: new_account ? "invitation" : "password")
  end
end

# frozen_string_literal: true

# A signed timestamp stamped into the signup form when it is served, so
# handle_signup can tell how long ago the visitor loaded the page. Real people
# take seconds to type an email and a password; the account-creation scripts
# that hit /signup fetch the form (for the CSRF token) and post it back
# instantly. Anything under MIN_AGE is refused and the form is re-rendered
# with the *same* token, so a genuinely fast human — password manager, one
# click — just presses the button again and passes.
#
# Stateless on purpose: nothing to store, and a token can't be forged without
# secret_key_base. Expires so a harvested token can't be replayed forever.
module SignupFormToken
  MIN_AGE = 3.seconds
  MAX_AGE = 24.hours
  PURPOSE = :signup_form

  module_function

  def generate(issued_at = Time.current)
    verifier.generate(issued_at.to_i, purpose: PURPOSE, expires_at: issued_at + MAX_AGE)
  end

  # Seconds since the token was issued, or nil when the token is missing,
  # tampered with, or expired.
  def age(token)
    return nil if token.blank?

    issued_at = verifier.verified(token.to_s, purpose: PURPOSE)
    return nil unless issued_at.is_a?(Integer)

    Time.current.to_i - issued_at
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end

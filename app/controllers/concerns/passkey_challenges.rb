# frozen_string_literal: true

# The one-time challenge a passkey step hands the device, kept in the session
# between the options and the answer (SignIn::Passkeys): five minutes, and
# taken back the first time it's used, so an answer can't be replayed.
module PasskeyChallenges
  extend ActiveSupport::Concern

  CHALLENGE_LASTS = 5.minutes

  private

  def passkey_relying_party
    SignIn::Passkeys.relying_party(request.base_url)
  end

  def keep_passkey_challenge(key, options)
    session[key] = { "challenge" => options.challenge, "at" => Time.current.to_i }
    options
  end

  def take_passkey_challenge(key)
    kept = session.delete(key)
    return nil unless kept.is_a?(Hash) && Time.zone.at(kept["at"].to_i) > CHALLENGE_LASTS.ago

    kept["challenge"]
  end
end

# frozen_string_literal: true

# Stateless, signed, expiring token that lets a payee (Person or Contractor) who
# has no CocoScout login open Stripe bank onboarding from a link we email them.
#
# Whitelisted to StripeConnectable payee types so a forged token can't name an
# arbitrary class. Stateless (no DB row) — the signature + expiry are the guard;
# links simply expire rather than being individually revocable.
module PayeeOnboardingToken
  EXPIRY = 30.days
  PURPOSE = "payee_onboarding"
  # Payee classes that carry a Stripe Connect account (see StripeConnectable).
  TYPE_NAMES = %w[Person Contractor].freeze

  module_function

  def generate(payee)
    type = payee.class.name
    raise ArgumentError, "unsupported payee type: #{type}" unless TYPE_NAMES.include?(type)

    verifier.generate({ "t" => type, "id" => payee.id }, expires_in: EXPIRY, purpose: PURPOSE)
  end

  # Returns the payee, or nil if the token is invalid/expired/tampered.
  def resolve(token)
    data = verifier.verify(token.to_s, purpose: PURPOSE)
    return nil unless data.is_a?(Hash) && TYPE_NAMES.include?(data["t"])

    data["t"].constantize.find_by(id: data["id"])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end

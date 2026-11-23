# frozen_string_literal: true

module SignIn
  # Checks an Apple or Google ID token: signed by the provider (its published
  # keys, cached for an hour and fetched again for a key we haven't seen),
  # issued by it, for us, not expired, and carrying the nonce this browser's
  # sign-in started with. Returns the claims, or raises Invalid.
  #
  #   SignIn::IdToken.verify("google", token, nonce: session_nonce)
  #   # => { "sub" => "…", "email" => "…", "email_verified" => true, … }
  class IdToken
    class Invalid < StandardError; end

    ISSUERS = {
      "google" => [ "https://accounts.google.com", "accounts.google.com" ],
      "apple" => [ "https://appleid.apple.com" ]
    }.freeze
    KEYS_URL = {
      "google" => "https://www.googleapis.com/oauth2/v3/certs",
      "apple" => "https://appleid.apple.com/auth/keys"
    }.freeze

    # subject: false for Apple's server notifications, which carry events, not a person.
    def self.verify(provider, token, nonce: nil, audiences: nil, subject: true)
      new(provider).verify(token, nonce: nonce, audiences: audiences, subject: subject)
    end

    def initialize(provider)
      @provider = provider.to_s
      raise Invalid, "unknown provider" unless ISSUERS.key?(@provider)
    end

    def verify(token, nonce:, audiences: nil, subject: true)
      audiences ||= default_audiences
      claims, = JWT.decode(token.to_s, nil, true,
                           algorithms: %w[RS256], jwks: method(:keys),
                           iss: ISSUERS.fetch(@provider), verify_iss: true,
                           aud: audiences, verify_aud: true, verify_expiration: true, leeway: 60)
      raise Invalid, "nonce" if nonce && !ActiveSupport::SecurityUtils.secure_compare(claims["nonce"].to_s, nonce.to_s)
      raise Invalid, "no subject" if subject && claims["sub"].blank?

      claims
    rescue JWT::DecodeError => e
      raise Invalid, e.class.name.demodulize
    end

    private

    def default_audiences
      @provider == "apple" ? [ Providers.apple_services_id, Providers::APPLE_BUNDLE_ID ].compact : [ Providers.google_client_id ].compact
    end

    # The jwt gem asks again with kid_not_found when the token's key isn't
    # among them: the provider rotated its keys, so fetch them fresh.
    def keys(options)
      cache_key = "sign_in/jwks/#{@provider}"
      Rails.cache.delete(cache_key) if options[:kid_not_found]
      jwks = Rails.cache.fetch(cache_key, expires_in: 1.hour) { fetch_keys }
      JWT::JWK::Set.new(jwks).filter { |key| key[:use].nil? || key[:use] == "sig" }
    end

    def fetch_keys
      response = Net::HTTP.get_response(URI(KEYS_URL.fetch(@provider)))
      raise Invalid, "keys unavailable" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end

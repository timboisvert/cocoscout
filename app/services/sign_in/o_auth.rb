# frozen_string_literal: true

module SignIn
  # The few HTTP calls to Apple and Google: where to send someone to sign in,
  # trading the code that comes back for an ID token, and (Apple) revoking a
  # connection. No OmniAuth: two providers, each a handful of lines.
  module OAuth
    class Error < StandardError; end

    GOOGLE_AUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth"
    GOOGLE_TOKEN = "https://oauth2.googleapis.com/token"
    APPLE_AUTHORIZE = "https://appleid.apple.com/auth/authorize"
    APPLE_TOKEN = "https://appleid.apple.com/auth/token"
    APPLE_REVOKE = "https://appleid.apple.com/auth/revoke"

    module_function

    def authorize_url(provider, redirect_uri:, state:, nonce:)
      case provider.to_s
      when "google"
        "#{GOOGLE_AUTHORIZE}?#{{ client_id: Providers.google_client_id, redirect_uri: redirect_uri, response_type: 'code',
                                 scope: 'openid email profile', state: state, nonce: nonce, prompt: 'select_account' }.to_query}"
      when "apple"
        # Apple sends the name and email only with form_post, as a cross-site
        # POST (ProvidersController#apple_callback).
        "#{APPLE_AUTHORIZE}?#{{ client_id: Providers.apple_services_id, redirect_uri: redirect_uri, response_type: 'code',
                                response_mode: 'form_post', scope: 'name email', state: state, nonce: nonce }.to_query}"
      else raise Error, "unknown provider"
      end
    end

    # => { id_token:, refresh_token: (Apple; kept to revoke later) }
    def exchange(provider, code:, redirect_uri:)
      body = case provider.to_s
      when "google"
               post_form(GOOGLE_TOKEN, client_id: Providers.google_client_id, client_secret: Providers.google_client_secret,
                                       code: code, redirect_uri: redirect_uri, grant_type: "authorization_code")
      when "apple"
               post_form(APPLE_TOKEN, client_id: Providers.apple_services_id, client_secret: apple_client_secret,
                                      code: code, redirect_uri: redirect_uri, grant_type: "authorization_code")
      else raise Error, "unknown provider"
      end
      raise Error, "no id token" if body["id_token"].blank?

      { id_token: body["id_token"], refresh_token: body["refresh_token"] }
    end

    # Apple requires that a disconnected Sign in with Apple is revoked, and
    # that deleting an account revokes it too. Best effort: a failure is logged.
    def revoke_apple(refresh_token, client_id: nil)
      return false if refresh_token.blank?

      post_form(APPLE_REVOKE, client_id: client_id.presence || Providers.apple_services_id, client_secret: apple_client_secret,
                              token: refresh_token, token_type_hint: "refresh_token")
      true
    rescue Error, StandardError => e
      Rails.logger.warn("[sign_in] Apple revoke failed: #{e.class}")
      false
    end

    # Apple's "client secret" is a short-lived token signed with our key.
    def apple_client_secret
      key = Providers.apple_private_key
      raise Error, "Apple key missing" unless key

      now = Time.current.to_i
      JWT.encode({ iss: Providers.apple_team_id, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: Providers.apple_services_id },
                 key, "ES256", { kid: Providers.apple_key_id })
    end

    def post_form(url, params)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.post(uri.path, URI.encode_www_form(params), "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json")
      end
      raise Error, "#{uri.host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body.present? ? JSON.parse(response.body) : {}
    end
  end
end

# frozen_string_literal: true

module SignIn
  # Continue with Apple and Continue with Google (sign-in plan phase 2; Tim,
  # 2026-11-22): whether each is set up, and who sees the buttons.
  #
  # Built on main behind a switch. Until SIGN_IN_WITH_PROVIDERS is "on", only
  # superadmins see them: on the Account page, and on the sign-in screen of a
  # browser a superadmin has used (a preview cookie, set while they're signed
  # in), so Apple, which can't send anyone back to localhost, can be tried on
  # cocoscout.com before everyone gets it.
  #
  # The settings (1Password item CocoScoutProductionPasswords, and .env):
  #   APPLE_TEAM_ID, APPLE_SERVICES_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY
  #   GOOGLE_SIGNIN_CLIENT_ID, GOOGLE_SIGNIN_CLIENT_SECRET
  module Providers
    LIST = %w[apple google].freeze
    NAMES = { "apple" => "Apple", "google" => "Google" }.freeze
    PREVIEW_COOKIE = :provider_sign_in_preview
    # The iPhone app's bundle id: Apple's server notifications are addressed to it.
    APPLE_BUNDLE_ID = "com.cocoscout.app"

    module_function

    def live?
      ENV["SIGN_IN_WITH_PROVIDERS"] == "on"
    end

    def configured?(provider)
      case provider.to_s
      when "apple" then [ apple_team_id, apple_services_id, apple_key_id ].all?(&:present?) && apple_private_key.present?
      when "google" then google_client_id.present? && google_client_secret.present?
      else false
      end
    end

    # Which buttons this visitor sees, in the order they're drawn: Apple first
    # on Apple devices, Google first elsewhere. None inside the apps, where
    # Google refuses to run in an embedded web view (native screens come later).
    def shown(user: nil, cookies: nil, user_agent: "")
      return [] if user_agent.to_s.include?("Turbo Native")
      return [] unless live? || user&.superadmin? || cookies&.signed&.[](PREVIEW_COOKIE).present?

      order = user_agent.to_s.match?(/iPhone|iPad|Macintosh|Mac OS X/) ? %w[apple google] : %w[google apple]
      order.select { |provider| configured?(provider) }
    end

    def name(provider) = NAMES.fetch(provider.to_s)

    def apple_team_id = ENV["APPLE_TEAM_ID"].presence
    def apple_services_id = ENV["APPLE_SERVICES_ID"].presence
    def apple_key_id = ENV["APPLE_KEY_ID"].presence
    def google_client_id = ENV["GOOGLE_SIGNIN_CLIENT_ID"].presence
    def google_client_secret = ENV["GOOGLE_SIGNIN_CLIENT_SECRET"].presence

    # The Sign in with Apple key (.p8). Deploy settings arrive one line each,
    # so its line breaks may come as real ones, as "\n", or as spaces: the
    # body is read whichever way it arrived.
    def apple_private_key
      raw = ENV["APPLE_PRIVATE_KEY"].to_s
      return nil if raw.blank?

      body = raw.gsub("\\n", "\n").sub("-----BEGIN PRIVATE KEY-----", "").sub("-----END PRIVATE KEY-----", "").gsub(/\s+/, "")
      OpenSSL::PKey.read(Base64.strict_decode64(body))
    rescue ArgumentError, OpenSSL::PKey::PKeyError
      nil
    end
  end
end

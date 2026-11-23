# frozen_string_literal: true

module SignIn
  # Passkeys (sign-in plan phase 4): making one for a signed-in account, and
  # signing in with one. The browser (navigator.credentials), the iPhone
  # (AuthenticationServices), and Android (Credential Manager) all speak
  # WebAuthn; the webauthn gem checks what they send.
  #
  # Each step is two calls: the options (with a one-time challenge the caller
  # keeps in the session), then the answer the device sent back, checked
  # against that challenge. A passkey is only ever made by someone already
  # signed in, so signing in with one needs no further proof.
  module Passkeys
    class Invalid < StandardError; end

    # cocoscout.com in production, so a passkey made on the website also
    # works in both apps (apple-app-site-association's webcredentials and
    # assetlinks.json's get_login_creds name the apps). Elsewhere, the host
    # the page is on (localhost in development).
    PRODUCTION_RP_ID = "cocoscout.com"
    PRODUCTION_ORIGINS = %w[https://cocoscout.com https://www.cocoscout.com].freeze

    # What the Account page calls a passkey, from the AAGUID its password
    # manager stamps on it (the passkey-authenticator-aaguids list). Any other
    # is named after the device it was made on.
    NAMES_BY_AAGUID = {
      "fbfc3007-154e-4ecc-8c0b-6e020557d7bd" => "iCloud Keychain",
      "dd4ec289-e01d-41c9-bb89-70fa845d4bf2" => "iCloud Keychain",
      "ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4" => "Google Password Manager",
      "adce0002-35bc-c60a-648b-0b25f1f05503" => "Chrome on Mac",
      "08987058-cadc-4b81-b6e1-30de50dcbe96" => "Windows Hello",
      "9ddd1817-af5a-4672-a2b9-3e3dd95000a9" => "Windows Hello",
      "6028b017-b1d4-4c02-b4b3-afcdafc96bb2" => "Windows Hello",
      "bada5566-a7aa-401f-bd96-45619a55120d" => "1Password",
      "d548826e-79b4-db40-a3d8-11116f7e8349" => "Bitwarden",
      "531126d6-e717-415c-9320-3d9aa6981239" => "Dashlane",
      "53414d53-554e-4700-0000-000000000000" => "Samsung Pass"
    }.freeze

    module_function

    def relying_party(base_url)
      production = Rails.env.production?
      WebAuthn::RelyingParty.new(
        name: "CocoScout",
        id: production ? PRODUCTION_RP_ID : URI(base_url).host,
        allowed_origins: (production ? PRODUCTION_ORIGINS : [ base_url ]) + android_origins
      )
    end

    # The Android app signs its passkeys from "android:apk-key-hash:" and its
    # signing certificate's SHA-256 (the same certificates assetlinks.json
    # names), not from a web address.
    def android_origins
      AndroidAssetLinksController::CERTIFICATES.map do |fingerprint|
        "android:apk-key-hash:#{Base64.urlsafe_encode64([ fingerprint.delete(':') ].pack('H*'), padding: false)}"
      end
    end

    # Options for making a passkey for a signed-in account. Its existing
    # passkeys are excluded, so a password manager that already holds one for
    # this account says so instead of making a second.
    def registration_options(user, relying_party:)
      relying_party.options_for_registration(
        user: { id: user.webauthn_handle, name: user.email_address, display_name: user.person&.name.presence || user.email_address },
        exclude: user.passkeys.pluck(:external_id),
        authenticator_selection: { resident_key: "required", require_resident_key: true, user_verification: "required" }
      )
    end

    # Checks the device's new passkey against the challenge and keeps it.
    def register!(user, credential, challenge:, relying_party:, user_agent: nil)
      raise Invalid, "no challenge" if challenge.blank?

      made = relying_party.verify_registration(credential_hash(credential), challenge, user_verification: true)
      raise Invalid, "not verified" unless made
      raise Invalid, "already kept" if Passkey.exists?(external_id: made.id)

      passkey = user.passkeys.create!(
        external_id: made.id, public_key: made.public_key, sign_count: made.sign_count,
        transports: Array(made.response.transports).map(&:to_s),
        name: NAMES_BY_AAGUID[made.response.authenticator_data.aaguid.to_s] || "Made on #{DeviceLabel.device_name(user_agent.to_s) || 'a device'}",
        last_used_at: Time.current
      )
      notify_added(user, passkey)
      passkey
    rescue WebAuthn::Error => e
      raise Invalid, e.class.name
    end

    # Options for signing in: no account named, so the device offers every
    # passkey it holds for this site (and the website's email field offers
    # them in its autofill).
    def authentication_options(relying_party:)
      relying_party.options_for_authentication(user_verification: "required")
    end

    # The passkey the device signed with, checked against the challenge.
    # Returns the Passkey; its user is who signed in.
    def authenticate(credential, challenge:, relying_party:)
      raise Invalid, "no challenge" if challenge.blank?

      passkey = nil
      used, = relying_party.verify_authentication(credential_hash(credential), challenge, user_verification: true) do |presented|
        passkey = Passkey.find_by(external_id: presented.id)
        raise Invalid, "unknown passkey" unless passkey

        passkey
      end
      raise Invalid, "not verified" unless used

      passkey.update_columns(sign_count: used.sign_count, last_used_at: Time.current)
      passkey
    rescue WebAuthn::Error => e
      raise Invalid, e.class.name
    end

    # A new key to the account: an email and a notification, as for Apple or
    # Google (the sign-in plan's rule 6), so a passkey nobody meant to add gets
    # noticed.
    def notify_added(user, passkey)
      rendered = ContentTemplateService.render("auth_passkey_added", {
        first_name: user.person&.name.to_s.split.first.presence || "there",
        passkey_name: passkey.shown_name,
        account_url: Rails.application.routes.url_helpers.account_url(**(Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }))
      })
      AuthMailer.method_connected(user, subject: rendered[:subject], body: rendered[:body]).deliver_later
      Notifier.deliver_rendered(user: user, category: "account", kind: "auth_passkey_added",
                                subject: rendered[:subject], body: rendered[:body], push_body: rendered[:push_body])
    rescue StandardError => e
      # The passkey stands even if the notice couldn't be written.
      Rails.logger.error("[passkeys] added notice for user #{user.id} failed: #{e.class}: #{e.message}")
    end

    # What the device sent, as a plain hash: from JSON params, or a JSON string.
    def credential_hash(credential)
      hash = credential.is_a?(String) ? JSON.parse(credential) : credential
      hash = hash.to_unsafe_h if hash.respond_to?(:to_unsafe_h)
      hash.to_h.deep_stringify_keys
    rescue JSON::ParserError
      raise Invalid, "unreadable"
    end
  end
end

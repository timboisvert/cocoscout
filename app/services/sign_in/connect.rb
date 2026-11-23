# frozen_string_literal: true

module SignIn
  # Attaches an Apple or Google account to a CocoScout account as one more way
  # in, and tells the person by email and notification (the sign-in plan's
  # safety rule; Tim, 2026-11-22).
  #
  # proof: how we know it's theirs.
  #   :password   they entered the account's own password: it keeps working
  #   :signed_in  they were signed in and connected it from the Account page
  #   :code       a code sent to the account's address
  #   :provider   the provider confirmed the address of an account with no
  #               chosen password
  #   :new_account  the account was just made with this provider: nothing to
  #               replace, and the welcome email goes in place of the notice
  # A code or the provider replaces the password with one nobody knows and
  # signs out everywhere else, so an account someone else set up under this
  # address (bots have) can't stay in.
  class Connect
    class Taken < StandardError; end

    def self.call(**) = new(**).call

    def initialize(user:, profile:, proof:)
      @user = user
      @profile = profile
      @proof = proof
    end

    def call
      existing = UserIdentity.find_by(provider: @profile.provider, uid: @profile.uid)
      raise Taken if existing && existing.user_id != @user.id
      return existing if existing

      identity = nil
      User.transaction do
        identity = @user.user_identities.create!(
          provider: @profile.provider, uid: @profile.uid, email: @profile.email, private_email: @profile.private_email,
          refresh_token: @profile.refresh_token,
          client_id: @profile.provider == "apple" ? Providers.apple_services_id : Providers.google_client_id,
          last_used_at: Time.current
        )
        # The provider, a code, or the password just proved the address.
        @user.update_column(:email_verified_at, Time.current) unless @proof == :signed_in
        @user.forget_password! if replaces_password?
      end
      notify(identity) unless @proof == :new_account
      identity
    end

    def replaces_password? = %i[code provider].include?(@proof)

    private

    def notify(identity)
      name = Providers.name(identity.provider)
      rendered = ContentTemplateService.render("auth_method_connected", {
        first_name: @user.person&.name.to_s.split.first.presence || "there",
        provider: name,
        provider_email: identity.private_email ? "a private #{name} address" : identity.email.to_s,
        password_line: replaces_password? ? "If this account had a password, it no longer works. Choose a new one on your Account page whenever you like." : "Your password still works too.",
        account_url: Rails.application.routes.url_helpers.account_url(**(Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }))
      })
      AuthMailer.method_connected(@user, subject: rendered[:subject], body: rendered[:body]).deliver_later
      Notifier.deliver_rendered(user: @user, category: "account", kind: "auth_method_connected",
                                subject: rendered[:subject], body: rendered[:body], push_body: rendered[:push_body])
    rescue StandardError => e
      # The connection stands even if the notice couldn't be written.
      Rails.logger.error("[sign_in] connected notice for user #{@user.id} failed: #{e.class}: #{e.message}")
    end
  end
end

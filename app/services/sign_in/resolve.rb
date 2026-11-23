# frozen_string_literal: true

module SignIn
  # The one place that decides what happens when Apple or Google says who
  # someone is (the sign-in plan's "After Apple or Google"; Tim, 2026-11-22).
  # The web pages only show the step it names; the app screens will too.
  #
  #   result = SignIn::Resolve.call(profile)
  #   result.kind  # :known        a connected Apple or Google account: sign in
  #                # :connected    matched an account with no chosen password: connected now, sign in
  #                # :needs_proof  matched an account with a chosen password (or a superadmin): connect once
  #                # :needs_email  no usable address (Apple's Hide My Email): add your email address
  #                # :new_account  an address we've never seen: create your account
  #   result.user  # the account, where there is one
  class Resolve
    # What the provider said, in one shape for both.
    Profile = Data.define(:provider, :uid, :email, :email_verified, :private_email, :first_name, :last_name, :refresh_token) do
      def self.from_claims(provider, claims, name: {}, refresh_token: nil)
        new(provider: provider.to_s, uid: claims["sub"].to_s, email: claims["email"].to_s.strip.downcase.presence,
            email_verified: ActiveModel::Type::Boolean.new.cast(claims["email_verified"]) == true,
            private_email: ActiveModel::Type::Boolean.new.cast(claims["is_private_email"]) == true,
            first_name: (name["first_name"].presence || claims["given_name"]).to_s.squish.presence,
            last_name: (name["last_name"].presence || claims["family_name"]).to_s.squish.presence,
            refresh_token: refresh_token.presence)
      end

      # An address we can find and keep an account under: confirmed by the
      # provider, and a real one (an Apple relay address only reaches the
      # person through Apple, and organizations know them by their own).
      def usable_email = (email if email.present? && email_verified && !private_email)

      def to_session = to_h.transform_keys(&:to_s)

      def self.from_session(hash) = new(**hash.to_h.symbolize_keys.slice(*members))
    end

    Result = Data.define(:kind, :user)

    def self.call(profile) = new(profile).call

    def initialize(profile)
      @profile = profile
    end

    def call
      if (identity = UserIdentity.find_by(provider: @profile.provider, uid: @profile.uid))
        identity.update_columns(last_used_at: Time.current)
        return Result.new(kind: :known, user: identity.user)
      end

      email = @profile.usable_email
      return Result.new(kind: :needs_email, user: nil) unless email

      user = User.find_by(email_address: email)
      return Result.new(kind: :new_account, user: nil) unless user
      # password_set_at only decides which step shows, never what's safe: an
      # account with a chosen password connects once with it (or a code), and
      # a superadmin always needs the password.
      return Result.new(kind: :needs_proof, user: user) if user.superadmin? || user.password_chosen?

      Connect.call(user: user, profile: @profile, proof: :provider)
      Result.new(kind: :connected, user: user)
    end
  end
end

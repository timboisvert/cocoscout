# frozen_string_literal: true

module SignIn
  # Sends and checks the 6-digit codes (SignInCode). One place, so the web
  # pages today and the app's own screens later send and check them alike.
  class Code
    # "10 minutes": what the pages and the email promise, straight from the model.
    def self.lifetime_in_words
      minutes = SignInCode::LIFETIME.in_minutes.round
      "#{minutes} #{'minute'.pluralize(minutes)}"
    end

    # Emails a fresh code. Returns :sent, or why not: :too_soon, :too_many.
    def self.deliver(email:, purpose:, user: nil, ip_address: nil)
      refusal = SignInCode.send_refusal(email)
      return refusal if refusal

      _record, code = SignInCode.issue!(email: email, purpose: purpose, user: user, ip_address: ip_address)
      AuthMailer.sign_in_code(email.to_s.strip.downcase, code).deliver_later
      :sent
    end

    # [:ok, SignInCode] or [:wrong | :expired | :locked, nil].
    def self.redeem(email:, purpose:, code:)
      SignInCode.redeem(email: email, purpose: purpose, code: code)
    end
  end
end

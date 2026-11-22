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
      refusal = SignInCode.send_refusal(email, purpose)
      return refusal if refusal

      _record, code = SignInCode.issue!(email: email, purpose: purpose, user: user, ip_address: ip_address)
      AuthMailer.sign_in_code(email.to_s.strip.downcase, seal(code)).deliver_later
      :sent
    end

    # The code goes to the mail job encrypted, so it never sits in plain text
    # in the job's logged arguments or its queue row (found testing 1.4 from
    # main, 2026-11-22). Only the mailer opens it; it expires with the code.
    def self.seal(code)
      encryptor.encrypt_and_sign(code.to_s, expires_in: SignInCode::LIFETIME, purpose: :sign_in_code_mail)
    end

    def self.unseal(sealed)
      encryptor.decrypt_and_verify(sealed.to_s, purpose: :sign_in_code_mail)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def self.encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new(
        Rails.application.key_generator.generate_key("sign_in/code mail", ActiveSupport::MessageEncryptor.key_len)
      )
    end
    private_class_method :encryptor

    # [:ok, SignInCode] or [:wrong | :expired | :locked, nil].
    def self.redeem(email:, purpose:, code:)
      SignInCode.redeem(email: email, purpose: purpose, code: code)
    end
  end
end

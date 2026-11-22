# frozen_string_literal: true

# A 6-digit code we emailed to an address: to sign in, to confirm the address
# of a new account, and later to connect a sign-in method or change an email.
# A code, never a link, so a mail scanner that opens every link can't use it
# up. Only a digest is stored. The sign-in pages quote LIFETIME, so change it
# here and the copy follows.
class SignInCode < ApplicationRecord
  LIFETIME = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_AFTER = 30.seconds
  SENDS_PER_HOUR = 5
  PURPOSES = %w[sign_in confirm_address connect change_email].freeze

  belongs_to :user, optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :purpose, inclusion: { in: PURPOSES }

  scope :live, -> { where(used_at: nil).where("expires_at > ?", Time.current) }
  scope :for_address, ->(email) { where(email: email.to_s.strip.downcase) }

  # Why a new code can't go out right now: :too_soon (one went out moments
  # ago) or :too_many (this address has had its share for the hour). nil when
  # it can.
  def self.send_refusal(email)
    recent = for_address(email).where("created_at > ?", 1.hour.ago)
    return :too_many if recent.count >= SENDS_PER_HOUR
    return :too_soon if recent.where("created_at > ?", RESEND_AFTER.ago).exists?

    nil
  end

  # Makes a new code for this address and purpose, ending any earlier one.
  # Returns [record, the code itself]; the code is never readable again.
  def self.issue!(email:, purpose:, user: nil, ip_address: nil)
    code = format("%06d", SecureRandom.random_number(1_000_000))
    transaction do
      for_address(email).live.where(purpose: purpose).update_all(expires_at: Time.current)
      record = create!(email: email, purpose: purpose, user: user, ip_address: ip_address,
                       code_digest: digest(email, code), expires_at: LIFETIME.from_now)
      [ record, code ]
    end
  end

  # Tries a code against the newest live one for this address and purpose.
  # Returns [:ok, record], or [:wrong | :expired | :locked, nil]. A right code
  # is used up; a wrong one counts against MAX_ATTEMPTS.
  def self.redeem(email:, purpose:, code:)
    record = for_address(email).live.where(purpose: purpose).order(:created_at).last
    return [ :expired, nil ] unless record
    return [ :locked, nil ] if record.attempts >= MAX_ATTEMPTS

    given = digest(email, code.to_s.gsub(/\D/, ""))
    if ActiveSupport::SecurityUtils.secure_compare(record.code_digest, given)
      record.update!(used_at: Time.current)
      [ :ok, record ]
    else
      record.increment!(:attempts)
      [ record.attempts >= MAX_ATTEMPTS ? :locked : :wrong, nil ]
    end
  end

  def self.digest(email, code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{email.to_s.strip.downcase}:#{code}")
  end
end

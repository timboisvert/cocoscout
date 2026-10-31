# frozen_string_literal: true

module Ticketing
  # Proving a buyer's email with an emailed code (advanced ticketing D7):
  # send_code! makes a code and emails it; check! consumes it. The caller
  # then sets the thirty-day cookie (VerifiedBuyer#verify_buyer!).
  class BuyerVerification
    class Error < StandardError; end

    def self.send_code!(organization, email)
      email = email.to_s.strip.downcase
      raise Error, "Type the email you used." unless email.match?(URI::MailTo::EMAIL_REGEXP)
      raise Error, "We just sent a code. Give it a minute, then try again." if organization.ticket_buyer_verifications.live.where(email: email).where("created_at > ?", 1.minute.ago).exists?

      code = format("%06d", SecureRandom.random_number(1_000_000))
      organization.ticket_buyer_verifications.live.where(email: email).update_all(consumed_at: Time.current)
      organization.ticket_buyer_verifications.create!(email: email, code_digest: TicketBuyerVerification.digest(code), expires_at: TicketBuyerVerification::TTL.from_now)
      TicketMembershipMailer.code(organization, email, code).deliver_later
      email
    end

    # True when the code is the live one for this email; a wrong code counts
    # a try, and five tries spend the code.
    def self.check!(organization, email, code)
      email = email.to_s.strip.downcase
      verification = organization.ticket_buyer_verifications.live.where(email: email).order(:id).last
      raise Error, "That code ran out. Ask for a new one." unless verification

      if verification.matches?(code)
        verification.update!(consumed_at: Time.current)
        true
      else
        verification.increment!(:attempts)
        verification.update!(consumed_at: Time.current) if verification.attempts >= TicketBuyerVerification::MAX_ATTEMPTS
        raise Error, verification.consumed_at ? "Too many tries. Ask for a new code." : "That's not the code we sent. Check the email and try again."
      end
    end
  end
end

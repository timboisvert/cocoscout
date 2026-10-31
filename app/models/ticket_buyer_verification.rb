# frozen_string_literal: true

# A six-digit code emailed to a buyer to prove an email address (advanced
# ticketing D7): good for fifteen minutes and five tries, then a signed
# per-organization cookie for thirty days (VerifiedBuyer). Memberships use
# it today; the buyer hub (V1.6) will too.
class TicketBuyerVerification < ApplicationRecord
  TTL = 15.minutes
  MAX_ATTEMPTS = 5

  belongs_to :organization

  scope :live, ->(at = Time.current) { where(consumed_at: nil).where("expires_at > ?", at) }

  def self.digest(code) = Digest::SHA256.hexdigest(code.to_s)

  def matches?(code) = code_digest == self.class.digest(code.to_s.strip)
end

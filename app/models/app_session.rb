# frozen_string_literal: true

# One phone signed in to the app (Tim, 2026-10-12). The token is shown to the
# app once and kept only as a digest. Signing out in the app ends it, the
# Account page can end it, and changing the password ends them all. Unused
# for 30 days, it stops working on its own.
class AppSession < ApplicationRecord
  IDLE_EXPIRY = 30.days

  belongs_to :user
  has_many :device_tokens, dependent: :destroy

  scope :live, -> { where("last_used_at > ?", IDLE_EXPIRY.ago) }

  # Returns [session, token]; the token is never stored.
  def self.start!(user, device_name: nil, user_agent: nil, ip_address: nil)
    token = SecureRandom.base58(40)
    session = create!(user: user, token_digest: digest(token), device_name: device_name.to_s.squish.truncate(80).presence,
                      user_agent: user_agent.to_s.truncate(255).presence, ip_address: ip_address, last_used_at: Time.current)
    [ session, token ]
  end

  def self.authenticate(token)
    return nil if token.blank?

    session = live.includes(:user).find_by(token_digest: digest(token))
    return nil unless session

    session.update_column(:last_used_at, Time.current) if session.last_used_at < 1.hour.ago
    session
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  # The name the app sent, or a guess from its user agent.
  def label
    return device_name if device_name.present?

    case user_agent.to_s
    when /iPad/ then "iPad"
    when /iPhone|iOS/ then "iPhone"
    when /Android/ then "Android phone"
    else "A phone"
    end
  end
end

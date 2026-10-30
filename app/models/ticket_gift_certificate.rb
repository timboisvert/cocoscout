# frozen_string_literal: true

# A gift certificate: a dollar value a manager issued, spent at checkout
# instead of a card (TicketGiftCertificates does the holding, redeeming and
# refunding). It's payment, not a discount: the order's total, tax and fees
# are what they'd be with a card; the certificate pays part or all, and the
# card pays the rest. Whatever's left stays on the code for next time; a
# code with nothing left is spent. Good for every show the organization
# sells, or only the productions and dates in its scopes.
#
# Barebones (Tim, 2026-10-30): issued by hand, redeemed on the web checkout
# only, not sold online or at the door, no balance lookup for buyers yet.
class TicketGiftCertificate < ApplicationRecord
  SCOPES = %w[any some].freeze
  # No 0/O or 1/I, so a code reads right over the phone. Twelve characters
  # from 31 is about 59 bits: with the checkout's tries capped (rack_attack,
  # TicketCheckoutsController), guessing one is hopeless.
  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze
  CODE_LENGTH = 12
  CODE_FORMAT = /\AGIFT-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}\z/
  CODE_EXAMPLE = "GIFT-XXXX-XXXX-XXXX"

  belongs_to :organization
  belongs_to :issued_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  has_many :scopes, class_name: "TicketGiftCertificateScope", dependent: :destroy
  has_many :redemptions, class_name: "TicketGiftCertificateRedemption", dependent: :destroy
  has_many :ticket_orders, dependent: :nullify
  has_many :ticket_purchases, dependent: :nullify

  normalizes :code, with: ->(c) { c.to_s.strip.upcase }
  normalizes :recipient_email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :remaining_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scope, inclusion: { in: SCOPES }
  validates :recipient_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :recipient_name, :note, length: { maximum: 200 }

  before_validation :assign_code, on: :create
  before_validation { self.remaining_cents = amount_cents if remaining_cents.nil? }

  scope :live, -> { where(voided_at: nil) }

  # A code as a buyer typed it: "gift 7k3m q9xd n4pw" is GIFT-7K3M-Q9XD-N4PW.
  def self.normalize_code(raw)
    letters = raw.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    letters = letters.delete_prefix("GIFT")
    return raw.to_s.strip.upcase if letters.length != CODE_LENGTH

    "GIFT-#{letters.scan(/.{4}/).join('-')}"
  end

  def self.generate_code
    loop do
      body = Array.new(CODE_LENGTH) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join
      code = "GIFT-#{body.scan(/.{4}/).join('-')}"
      return code unless exists?(code: code)
    end
  end

  def voided?
    voided_at.present?
  end

  def spent?
    !voided? && remaining_cents.zero?
  end

  # Can pay for something right now.
  def usable?
    !voided? && remaining_cents.positive?
  end

  # Good for this date? Any show, or one of its scopes names the date's
  # production (every date) or the date itself.
  def covers?(listing)
    return true if scope == "any"

    scopes.any? do |s|
      s.production_id == listing.production_id && (s.ticket_listing_id.nil? || s.ticket_listing_id == listing.id)
    end
  end

  # "any show", "Late Night Cabaret", "Late Night Cabaret (3 dates) and
  # Winter Follies": what it's good for, in words.
  def good_for_words
    return "any show" if scope == "any"

    scopes.includes(:production).group_by(&:production).map do |production, rows|
      dates = rows.count(&:ticket_listing_id)
      dates.positive? ? "#{production.name} (#{dates} #{'date'.pluralize(dates)})" : production.name
    end.sort.to_sentence
  end

  # The productions it's good for, by name (for a buyer told where it works).
  def production_names
    scopes.includes(:production).map { |s| s.production.name }.uniq.sort
  end

  def status_words
    return "Voided" if voided?
    return "Used" if spent?
    return "Unused" if remaining_cents == amount_cents

    "#{ActiveSupport::NumberHelper.number_to_currency(remaining_cents / 100.0)} left"
  end

  private

  def assign_code
    self.code = self.class.generate_code if code.blank?
  end
end

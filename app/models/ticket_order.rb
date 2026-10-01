# frozen_string_literal: true

# One purchase: a buyer's tickets for one listing, and every cent of it —
# face value, discount, tax, our fee, card processing, what the buyer paid and
# what the theater keeps (see TicketPricing). Door cash sales and comps are
# orders too, so the door count and the books see everything.
#
# A pending online order holds its seats until expires_at; paying it turns its
# reserved tickets valid. money_path says where the money went: through
# CocoScout, through another site (Eventbrite, later), cash at the door, or
# nowhere (comps).
class TicketOrder < ApplicationRecord
  STATUSES = %w[pending paid expired canceled refunded partially_refunded].freeze
  CHANNELS = %w[online embed door_cash comp].freeze
  MONEY_PATHS = %w[cocoscout external cash none].freeze
  # Seats stay reserved this long while a buyer pays.
  HOLD = 10.minutes
  # Short, unambiguous order codes for people to read out at the door.
  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze

  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_discount_code, optional: true
  belongs_to :user, optional: true
  # Who gave a comp from the show page.
  belongs_to :issued_by, class_name: "User", optional: true

  has_many :tickets, dependent: :destroy
  has_many :ticket_refunds, dependent: :delete_all

  normalizes :buyer_email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :channel, inclusion: { in: CHANNELS }
  validates :money_path, inclusion: { in: MONEY_PATHS }
  validates :fee_mode, inclusion: { in: TicketingProfile::FEE_MODES }
  validates :code, :token, presence: true, uniqueness: true
  validates :buyer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true

  before_validation :assign_code_and_token, on: :create

  scope :paid_like, -> { where(status: %w[paid partially_refunded]) }
  scope :holding, ->(at = Time.current) { where(status: "pending").where("ticket_orders.expires_at > ?", at) }
  scope :stale, ->(at = Time.current) { where(status: "pending").where("ticket_orders.expires_at <= ?", at) }

  def pending?
    status == "pending"
  end

  def paid?
    %w[paid partially_refunded].include?(status)
  end

  def hold_expired?(at = Time.current)
    pending? && expires_at.present? && expires_at <= at
  end

  def to_param
    token
  end

  private

  def assign_code_and_token
    self.token ||= SecureRandom.urlsafe_base64(24)
    return if code.present?

    loop do
      self.code = Array.new(6) { CODE_ALPHABET.sample(random: SecureRandom) }.join
      break unless self.class.exists?(code: code)
    end
  end
end

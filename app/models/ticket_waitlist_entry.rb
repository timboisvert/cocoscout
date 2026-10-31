# frozen_string_literal: true

# Someone waiting for a sold-out date (advanced ticketing plan §7b). Entries
# are offered returned seats in turn (Ticketing::Waitlist): an offer is a
# pending order held for the offer window, with a checkout link by email; a
# missed offer passes to the next person. One live entry per email per date.
class TicketWaitlistEntry < ApplicationRecord
  STATUSES = %w[waiting offered bought missed removed].freeze
  LIVE_STATUSES = %w[waiting offered].freeze
  PREFERENCES = { "any" => "Any seats", "together" => "Only seats together" }.freeze
  # How long an offer holds its seats.
  OFFER_WINDOW = 30.minutes
  MAX_QUANTITY = 10

  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :offer_order, class_name: "TicketOrder", optional: true

  normalizes :email, with: ->(e) { e.to_s.strip.downcase.presence }
  normalizes :name, with: ->(n) { n.to_s.squish.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :quantity, numericality: { only_integer: true, in: 1..MAX_QUANTITY }
  validates :status, inclusion: { in: STATUSES }
  validates :preference, inclusion: { in: PREFERENCES.keys }
  validates :email, uniqueness: { scope: :ticket_listing_id, conditions: -> { where(status: LIVE_STATUSES) }, message: "is already on this date's list" }, if: -> { status.in?(LIVE_STATUSES) }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }
  before_validation { self.organization ||= ticket_listing&.organization }
  before_create { self.position = (ticket_listing.waitlist_entries.maximum(:position) || 0) + 1 if position.zero? }

  scope :live, -> { where(status: LIVE_STATUSES) }
  scope :waiting, -> { where(status: "waiting").order(:position, :id) }
  scope :offered, -> { where(status: "offered") }

  def to_param = token
  def waiting? = status == "waiting"
  def offered? = status == "offered"
  def live? = status.in?(LIVE_STATUSES)
  def first_name = name.to_s.split.first

  def status_label
    case status
    when "waiting" then "Waiting"
    when "offered" then "Offered, until #{offer_expires_at&.strftime('%-l:%M %p')}"
    when "bought" then "Bought"
    when "missed" then "Missed the offer"
    else "Left the list"
    end
  end
end

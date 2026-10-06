# frozen_string_literal: true

# One admission. Its code (in the QR) is what the door scans; a ticket sold on
# another site later carries that site's barcode too, so the same door finds
# it. "reserved" while its order is waiting to be paid; "valid" once paid.
class Ticket < ApplicationRecord
  # "exchanged": moved to another date, where a new ticket took its place.
  STATUSES = %w[reserved valid checked_in refunded void exchanged].freeze
  # Seats these take for good (reserved ones count only while their order's
  # hold lasts — see Ticketing::Inventory).
  SOLD_STATUSES = %w[valid checked_in].freeze

  belongs_to :ticket_order
  belongs_to :ticket_tier
  # The bundle it was bought in ("4 × General for $70"), if any.
  belongs_to :bundle_tier, class_name: "TicketTier", optional: true, inverse_of: :bundle_tickets
  belongs_to :ticket_listing
  # The pass this ticket came with ("Twilight Double Feature"), if any.
  belongs_to :ticket_pass, optional: true
  belongs_to :checked_in_by, class_name: "User", optional: true

  has_many :tax_lines, as: :taxable, dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }
  validates :code, presence: true, uniqueness: true
  validates :price_cents, :discount_cents, :tax_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :assign_code, on: :create

  scope :sold, -> { where(status: SOLD_STATUSES) }

  # What a guest list or the door calls it: "General", or "General (Twilight
  # Double Feature pass)" when it came with a pass.
  def type_label
    ticket_pass ? "#{ticket_tier.name} (#{ticket_pass.name} pass)" : ticket_tier.name
  end

  def checked_in?
    status == "checked_in"
  end

  private

  def assign_code
    self.code ||= SecureRandom.urlsafe_base64(16)
  end
end

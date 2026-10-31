# frozen_string_literal: true

# A group's block of seats for one date (advanced ticketing plan §3): a
# school, a company, a party. The seats are held (TicketQuantityHold) and
# invoiced (Invoice, numbered with the organization's others) the moment
# it's booked; paid in full, or issued early by the box office, the block
# becomes one ticket order on the group's name, with the names the leader
# pasted on the tickets. Unpaid by release_on, the seats go back on sale.
#
#   booked    seats held, invoice open
#   ticketed  tickets issued (paid, or trusted)
#   released  not paid in time: seats back on sale, invoice cancelled
#   canceled  the box office called it off
class TicketGroupBooking < ApplicationRecord
  STATUSES = %w[booked ticketed released canceled].freeze
  STATUS_LABELS = { "booked" => "Seats held", "ticketed" => "Tickets issued", "released" => "Released", "canceled" => "Canceled" }.freeze
  MAX_SEATS = 500
  # The box office hears about a block about to be released this many days
  # before, and so does the leader.
  WARNING_DAYS = 3

  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_tier
  belongs_to :invoice, optional: true
  belongs_to :ticket_order, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_one :quantity_hold, class_name: "TicketQuantityHold", as: :owner, dependent: :destroy

  normalizes :contact_email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :name, :contact_name, presence: true, length: { maximum: 120 }
  validates :contact_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :seat_count, numericality: { only_integer: true, in: 1..MAX_SEATS }
  validates :comp_count, numericality: { only_integer: true, in: 0..MAX_SEATS }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :due_on, :release_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :dates_make_sense

  before_validation { self.token ||= SecureRandom.urlsafe_base64(18) }
  before_validation { self.organization ||= ticket_listing&.organization }

  scope :live, -> { where(status: %w[booked ticketed]) }
  scope :booked, -> { where(status: "booked") }

  def to_param = token
  def booked? = status == "booked"
  def ticketed? = status == "ticketed"
  def live? = status.in?(%w[booked ticketed])
  def status_label = STATUS_LABELS.fetch(status, status.humanize)
  # Every seat in the block: the paid ones and the chaperones'.
  def seats = seat_count + comp_count
  def total_cents = seat_count * price_cents
  def first_name = contact_name.to_s.split.first

  # The names the leader pasted, one a line, in ticket order.
  def names_list
    names.to_s.lines.map(&:squish).compact_blank
  end

  # The paid seats still to pay for, by the invoice.
  def paid? = invoice.nil? || invoice.paid? || total_cents.zero?

  private

  def dates_make_sense
    return if due_on.blank? || release_on.blank?

    errors.add(:release_on, "comes before the payment is due; give them until at least the due date") if release_on < due_on
    showtime = ticket_listing&.show&.date_and_time
    errors.add(:release_on, "is after the show") if showtime && release_on > showtime.to_date
  end
end

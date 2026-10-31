# frozen_string_literal: true

# A room drawn for selling seats (advanced ticketing plan §1): sections of
# rows, tables and standing areas, each seat with a place on the page. Drawn
# for one room and owned by Ticketing (the room never points back). A
# production or a date picks a chart; a ticket type's zone is a set of its
# sections. Its kind is what it holds: all seats is reserved, any standing
# area makes it mixed.
class SeatChart < ApplicationRecord
  STATUSES = %w[draft active archived].freeze
  # The page the seats sit on, in chart units (SVG viewBox).
  WIDTH = 1000
  PITCH = 30
  MARGIN = 40

  belongs_to :organization
  belongs_to :location_space
  has_many :sections, -> { order(:position, :id) }, class_name: "SeatSection", dependent: :destroy, inverse_of: :seat_chart
  has_many :seats, through: :sections
  has_many :production_ticketings, dependent: :nullify
  has_many :ticket_listings, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 }
  validates :status, inclusion: { in: STATUSES }

  scope :usable, -> { where(status: %w[draft active]) }

  def room = location_space
  def active? = status == "active"
  def archived? = status == "archived"

  # Seats that can be sold (killed ones aren't).
  def seat_count = seats.where(killed: false).count
  def standing_capacity = sections.standing.sum(:standing_capacity)
  def kind = sections.standing.exists? ? "mixed" : "reserved"
  def kind_label = kind == "mixed" ? "Seats and standing" : "Reserved seats"

  # Charts a listing or production is drawn from can't be removed, nor one
  # with a ticket on any of its seats.
  def in_use?
    production_ticketings.exists? || ticket_listings.exists? || Ticket.where(seat_section_id: sections.select(:id)).exists?
  end

  # The chart's height from its sections, for the SVG viewBox.
  def height
    [ sections.maximum(Arel.sql("y + height")).to_i + MARGIN, 200 ].max
  end

  # Lay the sections out again, top to bottom in order, each placing its own
  # seats (SeatSection#layout!). Called whenever a section is added, removed
  # or reordered.
  def relayout!
    y = MARGIN
    sections.each do |section|
      section.layout!(y: y)
      y += section.height + MARGIN
    end
  end

  # One label for a seat: "Orchestra C 14" when the chart has more than one
  # seated section, else "C 14".
  def seat_label(seat)
    sections.reject(&:standing?).size > 1 ? "#{seat.seat_section.name} #{seat.label}" : seat.label
  end
end

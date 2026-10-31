# frozen_string_literal: true

# One seat on a chart: its row and number, where it's drawn, what kind it is
# (a wheelchair space, a companion seat beside one, a seat with a restricted
# view), and whether it's killed (not for sale on any date from now on; a
# seat on a ticket is never deleted, only killed).
class Seat < ApplicationRecord
  KINDS = %w[standard wheelchair companion restricted_view].freeze
  KIND_LABELS = { "standard" => "Standard", "wheelchair" => "Wheelchair space", "companion" => "Companion seat", "restricted_view" => "Restricted view" }.freeze
  ACCESSIBLE_KINDS = %w[wheelchair companion].freeze

  belongs_to :seat_section, inverse_of: :seats
  has_many :tickets, dependent: :restrict_with_error
  has_many :ticket_seat_hold_seats, dependent: :destroy

  validates :row_label, :number, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :note, length: { maximum: 120 }
  before_validation { self.label = "#{row_label} #{number}" if row_label.present? && number }

  scope :live, -> { where(killed: false) }

  def kind_label = KIND_LABELS.fetch(kind)
  def accessible? = kind.in?(ACCESSIBLE_KINDS)
  def live? = !killed

  # "Orchestra C 14", through the chart's rule.
  def full_label = seat_section.seat_chart.seat_label(self)

  # A seat that's on a live ticket can't go.
  def on_a_ticket? = tickets.where(status: %w[reserved valid checked_in]).exists?
end

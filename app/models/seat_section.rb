# frozen_string_literal: true

# One part of a chart: rows of seats, tables with seats around them, or a
# standing area sold by count. A ticket type's zone is one or more sections.
# best_order says how Best available walks a seated section: from the center
# of each row out ("center") or from the front ("front").
class SeatSection < ApplicationRecord
  KINDS = %w[rows tables standing].freeze
  KIND_LABELS = { "rows" => "Rows of seats", "tables" => "Tables", "standing" => "Standing area" }.freeze
  BEST_ORDERS = %w[center front].freeze

  belongs_to :seat_chart, inverse_of: :sections
  has_many :seats, -> { order(:row_label, :number) }, dependent: :destroy, inverse_of: :seat_section
  has_many :ticket_tier_zones, dependent: :destroy
  has_many :tickets, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }
  validates :kind, inclusion: { in: KINDS }
  validates :best_order, inclusion: { in: BEST_ORDERS }
  validates :standing_capacity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :standing, -> { where(kind: "standing") }
  scope :seated, -> { where.not(kind: "standing") }

  def standing? = kind == "standing"
  def seated? = !standing?
  def kind_label = KIND_LABELS.fetch(kind)
  def live_seats = seats.where(killed: false)
  def live_seat_count = standing? ? standing_capacity : live_seats.count

  # Rows in order, each with its seats in number order.
  def rows
    seats.group_by(&:row_label).sort_by { |label, _| [ label.length, label ] }
  end

  # Add rows of seats: `count` rows from `first_row` ("A"), `per_row` seats
  # each, numbered from `first_number`. Tables: each row is a table of
  # `per_row` seats. Seats already there keep their ids (a seat on a ticket
  # must). Returns the seats made.
  def add_rows!(count:, per_row:, first_row: "A", first_number: 1)
    count = count.to_i.clamp(1, 60)
    per_row = per_row.to_i.clamp(1, 60)
    label = first_row.to_s.strip.upcase.presence || "A"
    made = []
    transaction do
      count.times do |r|
        row = next_row_label(label, r)
        per_row.times do |n|
          number = first_number.to_i + n
          made << seats.find_or_create_by!(row_label: row, number: number) { |s| s.label = "#{row} #{number}" }
        end
      end
      seat_chart.relayout!
    end
    made
  end

  # "A".."Z", then "AA", "AB"...; tables "T1", "T2"...
  def next_row_label(first, offset)
    return "#{first.sub(/\d+\z/, '')}#{first[/\d+\z/].to_i + offset}" if first.match?(/\d\z/)

    label = first.dup
    offset.times { label = label.succ }
    label
  end

  # Place every seat: rows top to bottom, seats left to right from the
  # center, 30 units apart; a table is a ring of seats. Sets this section's
  # box and each seat's best_rank (row from the front, then distance from
  # the row's middle).
  def layout!(y:)
    pitch = SeatChart::PITCH
    groups = rows
    self.x = SeatChart::MARGIN
    self.y = y
    if standing?
      self.width = SeatChart::WIDTH - 2 * SeatChart::MARGIN
      self.height = 80
    elsif kind == "tables"
      per_row = 4
      ring = 2 * pitch
      cell = ring * 2 + pitch
      self.width = SeatChart::WIDTH - 2 * SeatChart::MARGIN
      self.height = ((groups.size + per_row - 1) / per_row) * cell + 20
      groups.each_with_index do |(_, table_seats), t|
        cx = x + (t % per_row) * cell + cell / 2 + ((width - per_row * cell) / 2)
        cy = y + 20 + (t / per_row) * cell + cell / 2
        table_seats.each_with_index do |seat, i|
          angle = 2 * Math::PI * i / table_seats.size - Math::PI / 2
          seat.update_columns(x: (cx + ring * Math.cos(angle)).round, y: (cy + ring * Math.sin(angle)).round, best_rank: t * 100 + i, updated_at: Time.current)
        end
      end
    else
      widest = groups.map { |_, s| s.size }.max.to_i
      self.width = [ widest * pitch, 200 ].max
      self.height = groups.size * pitch + 20
      center = x + width / 2
      groups.each_with_index do |(_, row_seats), r|
        row_y = y + 20 + r * pitch
        offset = center - (row_seats.size - 1) * pitch / 2
        row_seats.each_with_index do |seat, i|
          from_middle = (i - (row_seats.size - 1) / 2.0).abs
          rank = best_order == "front" ? r * 1000 + i : r * 1000 + (from_middle * 2).round
          seat.update_columns(x: offset + i * pitch, y: row_y, best_rank: rank, updated_at: Time.current)
        end
      end
    end
    save!(validate: false)
  end
end

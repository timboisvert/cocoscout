# frozen_string_literal: true

# Seats kept off sale on one date (advanced ticketing plan §1): house seats,
# accessible seats kept for people who need them, a group's or a
# subscriber's block, seats sold on another site, or any seats the box office
# marks by hand. Live until released (by hand, or at release_at). The seats
# themselves are TicketSeatHoldSeat rows; the database keeps one hold per
# seat per date.
class TicketSeatHold < ApplicationRecord
  KINDS = %w[house accessible group subscription members outside_sale manual].freeze
  KIND_LABELS = { "house" => "House seats", "accessible" => "Accessible seating", "group" => "Group", "subscription" => "Subscription", "members" => "Members only",
                  "outside_sale" => "Sold on another site", "manual" => "Held" }.freeze

  belongs_to :organization
  belongs_to :ticket_subscription, optional: true
  belongs_to :ticket_listing
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :hold_seats, class_name: "TicketSeatHoldSeat", dependent: :destroy, inverse_of: :ticket_seat_hold
  has_many :seats, through: :hold_seats

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }

  scope :live, ->(at = Time.current) { where(released_at: nil).where("release_at IS NULL OR release_at > ?", at) }

  def live?(at = Time.current) = released_at.nil? && (release_at.nil? || release_at > at)
  def kind_label = KIND_LABELS.fetch(kind)

  def release!
    update!(released_at: Time.current) if released_at.nil?
  end

  # Take some seats out of the hold (sold from it, or given back); an empty
  # hold is released.
  def drop_seats!(seat_ids)
    hold_seats.where(seat_id: seat_ids).delete_all
    release! unless hold_seats.exists?
  end
end

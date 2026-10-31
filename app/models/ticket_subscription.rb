# frozen_string_literal: true

# A subscriber (advanced ticketing §2a): one person's standing in a
# subscription pass, the seats they keep on every date, and their renewal.
# Their page is /tickets/my-subscription/<token>.
class TicketSubscription < ApplicationRecord
  STATUSES = %w[pending active renewal_open renewed released canceled].freeze
  STATUS_LABELS = { "pending" => "Not paid", "active" => "Subscribed", "renewal_open" => "Renewal open", "renewed" => "Renewed",
                    "released" => "Not renewed", "canceled" => "Canceled" }.freeze

  belongs_to :organization
  belongs_to :ticket_pass
  belongs_to :ticket_purchase, optional: true
  belongs_to :follower, optional: true
  belongs_to :renewed_from, class_name: "TicketSubscription", optional: true
  belongs_to :renewal_pass, class_name: "TicketPass", optional: true
  has_many :seat_holds, class_name: "TicketSeatHold", dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :active, -> { where(status: %w[active renewal_open]) }

  def to_param = token
  def status_label = STATUS_LABELS.fetch(status)
  def first_name = buyer_name.to_s.split.first.presence || "there"

  def seats = Seat.where(id: seat_ids).includes(seat_section: :seat_chart).sort_by(&:best_rank)
  def seat_labels = seats.map(&:full_label)

  # The orders this subscription's purchase made, one per date.
  def orders = ticket_purchase ? ticket_purchase.ticket_orders.includes(ticket_listing: :show).to_a : []

  def renewable?(at = Time.current)
    status == "renewal_open" && renewal_pass && renewal_pass.status == "on_sale" && (renewal_pass.renewal_closes_at.nil? || renewal_pass.renewal_closes_at > at)
  end
end

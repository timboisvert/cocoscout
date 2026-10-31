# frozen_string_literal: true

# A membership an organization sells (advanced ticketing §2b), defined from
# a menu of perks, each on or off: a percentage off tickets, early access
# N days before public on-sale, free date exchanges, better seats (a
# members-only block of held seats), a free section upgrade, and anything
# else written as a line of its own. Nothing is bundled in by default.
class TicketMembershipLevel < ApplicationRecord
  STATUSES = %w[draft on_sale closed].freeze
  STATUS_LABELS = { "draft" => "Draft", "on_sale" => "On sale", "closed" => "Closed" }.freeze

  belongs_to :organization
  has_many :memberships, class_name: "TicketMembership", foreign_key: :ticket_membership_level_id, dependent: :restrict_with_error, inverse_of: :level

  validates :name, presence: true, length: { maximum: 80 }
  validates :status, inclusion: { in: STATUSES }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :period_months, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 36 }
  validates :discount_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :presale_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }

  scope :on_sale, -> { where(status: "on_sale") }
  scope :in_order, -> { order(:position, :id) }

  def status_label = STATUS_LABELS.fetch(status)

  def extras_list = extras.to_s.lines.map(&:strip).reject(&:blank?)

  # The perks, one line each, in plain words.
  def perk_words
    words = []
    words << "#{discount_percent}% off tickets" if discount_percent.positive?
    words << "Tickets #{presale_days} #{'day'.pluralize(presale_days)} before everyone else" if presale_days.positive?
    words << "Free date exchanges" if free_exchanges
    words << "Better seats: a block held for members" if better_seats
    words << "A free section upgrade when seats are free" if section_upgrade
    words + extras_list
  end

  def period_words
    period_months == 12 ? "a year" : "#{period_months} #{'month'.pluralize(period_months)}"
  end
end

# frozen_string_literal: true

# One pricing rule a manager wrote (advanced ticketing §7c): when a date is
# this far sold or this close, a ticket type (or every type) costs this
# much more or less. Rules are read top to bottom; the first that matches
# a date sets the price, within the type's floor and ceiling.
class TicketPriceRule < ApplicationRecord
  CONDITIONS = %w[sold_pct_at_least days_out_at_most sold_pct_below_by_days_out].freeze
  CONDITION_LABELS = {
    "sold_pct_at_least" => "When the date is this far sold",
    "days_out_at_most" => "When the date is this close",
    "sold_pct_below_by_days_out" => "When the date is this close and still under this far sold"
  }.freeze
  CHANGE_KINDS = %w[amount percent].freeze

  belongs_to :organization
  belongs_to :production_ticketing, inverse_of: :price_rules
  belongs_to :ticket_tier, optional: true
  has_many :price_changes, class_name: "TicketPriceChange", dependent: :nullify

  validates :condition, inclusion: { in: CONDITIONS }
  validates :change_kind, inclusion: { in: CHANGE_KINDS }
  validates :threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }
  validates :change_value, numericality: { only_integer: true, other_than: 0 }
  validates :name, length: { maximum: 80 }

  scope :enabled, -> { where(enabled: true) }
  scope :in_order, -> { order(:position, :id) }

  # Does this rule speak for this type? A date's copy of a production type
  # follows the rule written for the production's.
  def covers?(tier)
    ticket_tier_id.nil? || ticket_tier_id == tier.id || ticket_tier_id == tier.source_tier_id
  end

  # Does the date meet the condition right now?
  def matches?(listing, at: Time.current)
    days_out = ((listing.show.date_and_time - at) / 1.day).floor
    case condition
    when "days_out_at_most" then days_out <= days
    when "sold_pct_at_least" then (pct = sold_pct(listing)) && pct >= threshold
    when "sold_pct_below_by_days_out" then days_out <= days && (pct = sold_pct(listing)) && pct < threshold
    end
  end

  # Sold as a share of the date's capacity; nil when there's no capacity to
  # measure against (a rule about how far sold can't match then).
  def sold_pct(listing)
    inventory = listing.inventory
    capacity = inventory.capacity
    return nil if capacity.nil? || capacity.zero?

    (100.0 * (capacity - inventory.remaining.to_i) / capacity).floor
  end

  def apply(cents)
    changed = change_kind == "percent" ? (cents * (100 + change_value) / 100.0).round : cents + change_value
    [ changed, 0 ].max
  end

  def change_words
    sign = change_value.positive? ? "+" : "−"
    change_kind == "percent" ? "#{sign}#{change_value.abs}%" : "#{sign}#{ActiveSupport::NumberHelper.number_to_currency(change_value.abs / 100.0)}"
  end

  def condition_words
    case condition
    when "sold_pct_at_least" then "#{threshold}% sold or more"
    when "days_out_at_most" then days.zero? ? "the day of the show" : "#{days} #{'day'.pluralize(days)} out or closer"
    when "sold_pct_below_by_days_out" then "#{days} #{'day'.pluralize(days)} out or closer and under #{threshold}% sold"
    end
  end

  def words
    "#{ticket_tier ? ticket_tier.name : 'Every ticket type'} #{change_words} when #{condition_words}"
  end
end

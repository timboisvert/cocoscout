# frozen_string_literal: true

# Ticketing set up once for a whole production — the way most shows run, as
# repeating dates — modeled on how sign-ups handle repeating events:
#
#   which events  — all its performances (shows, classes, workshops), only
#                   some event types, or dates picked by hand
#                   (event_matching: all / event_types / manual)
#   when sales open — as soon as a date is listed, or N days before it
#                   (schedule_mode: immediate / relative), and online sales
#                   close at showtime or a set time before
#   the rest      — ticket types (each with its own seats) and prices, fees,
#                   the most per order, the page's words and notes
#
# Every included show gets a listing from this setup (ProductionTicketingDates),
# and shows added to the calendar later join on their own. A show can still
# change its own: a listing's blank field reads the production's
# (TicketListing#effective_*), and its ticket types are copies of these, kept in
# sync while the listing inherits_tiers (ProductionTicketingSync). The time
# always comes from the calendar.
class ProductionTicketing < ApplicationRecord
  EVENT_MATCHING = %w[all event_types manual].freeze
  SCHEDULE_MODES = %w[immediate relative].freeze

  belongs_to :organization
  belongs_to :production

  has_many :ticket_tiers, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :production_ticketing
  has_many :production_ticketing_shows, dependent: :delete_all
  has_many :production_ticketing_products, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :production_ticketing
  has_many :ticket_products, through: :production_ticketing_products
  has_many :selected_shows, through: :production_ticketing_shows, source: :show

  accepts_nested_attributes_for :ticket_tiers, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["id"].blank? && attrs["name"].blank? && attrs["price_cents"].to_i.zero? }

  validates :production_id, uniqueness: true
  validates :event_matching, inclusion: { in: EVENT_MATCHING }
  validates :schedule_mode, inclusion: { in: SCHEDULE_MODES }
  validates :opens_days_before, numericality: { only_integer: true, in: 1..365 }
  validates :online_close_minutes, numericality: { only_integer: true, in: 0..1440 }
  # Its own refund policy, or (blank) the box office's (RefundPolicy.for).
  normalizes :refund_policy, with: ->(value) { value.to_s.strip.presence }
  validates :refund_policy, inclusion: { in: RefundPolicy::KINDS }, allow_nil: true
  validates :refund_window_hours, numericality: { only_integer: true, in: 0..RefundPolicy::MAX_HOURS }, allow_nil: true
  validates :refund_policy_note, length: { maximum: RefundPolicy::NOTE_LIMIT }
  validates :fee_mode, inclusion: { in: TicketingProfile::FEE_MODES }, allow_nil: true
  validates :max_per_order, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validate :production_belongs_to_organization

  before_validation { self.organization ||= production&.organization }
  before_validation { self.event_type_filter = Array(event_type_filter).compact_blank.map(&:to_s).uniq }
  # The production's short code is issued the first time it's set up to sell.
  after_create_commit { ShortLink.canonical_for!(production) }

  # The production's setup, made (switched off) the first time anyone asks.
  def self.for(production)
    production.production_ticketing || production.create_production_ticketing!(organization: production.organization)
  rescue ActiveRecord::RecordNotUnique
    production.reload.production_ticketing
  end

  # The products upsold at this production's checkout, in order, priced as
  # this production sells them (TicketProductOffer). Archived products drop out.
  def product_offers
    production_ticketing_products.includes(:ticket_product).select { |row| row.ticket_product.archived_at.nil? }.map(&:offer)
  end

  # Every show of the production that has a listing.
  def listings
    TicketListing.where(production_id: production_id)
  end

  # The production's upcoming, uncanceled shows this setup sells.
  def matching_shows(now: Time.current)
    base = production.shows.where(canceled: false).where("shows.date_and_time > ?", now)
    # A date the theater kept out of sales ("Not this one" when it was made).
    base = base.where.not(id: excluded_show_ids) if excluded_show_ids.present?
    case event_matching
    when "event_types" then base.where(event_type: event_type_filter.presence || EventTypes.revenue_event_types)
    when "manual" then base.where(id: production_ticketing_shows.select(:show_id))
    else base.where(event_type: EventTypes.revenue_event_types)
    end
  end

  def matches_show?(show)
    matching_shows.exists?(id: show.id)
  end

  # When online sales open for a show: right away, or N days before it.
  def on_sale_at_for(starts_at)
    schedule_mode == "relative" && starts_at ? starts_at - opens_days_before.days : nil
  end

  # When online sales close for a show that starts at `starts_at`.
  def off_sale_at_for(starts_at)
    starts_at && starts_at - online_close_minutes.minutes
  end

  private

  def production_belongs_to_organization
    errors.add(:production, "belongs to another organization") if production && organization && production.organization_id != organization_id
  end
end

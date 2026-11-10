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
  # The ticket page's own words, when they differ from the production's.
  has_rich_text :description

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
  # Its own comp rules (own_comps on), or the box office's (CompRules).
  include CompRules
  validates :comps_limit, inclusion: { in: TicketingProfile::COMPS_LIMITS }, allow_nil: true
  validates :team_comps_limit, inclusion: { in: TicketingProfile::TEAM_COMPS_LIMITS }, allow_nil: true
  validates :comps_per_show, :team_comps_per_show, numericality: { only_integer: true, in: 0..10_000 }, allow_nil: true
  # Blank is all ages (AgeLimit).
  validates :minimum_age, numericality: { only_integer: true, in: AgeLimit::AGES }, allow_nil: true
  validate :production_belongs_to_organization

  # The ticket page's own address, /tickets/<org>/<page_key>, when it isn't
  # the production's public URL (blank: Production#ticket_page_key). A show
  # renamed after its links went out changes it here; the addresses it had
  # (old_page_keys) keep landing on the page.
  PAGE_KEY = /\A[a-z0-9][a-z0-9-]{2,29}\z/
  RESERVED_PAGE_KEYS = %w[passes checkout embed orders].freeze
  normalizes :page_key, with: ->(value) { value.to_s.strip.downcase.presence }
  before_validation { self.page_key = nil if page_key.present? && page_key == production&.public_key }
  validates :page_key, format: { with: PAGE_KEY, message: "must be 3 to 30 lowercase letters, numbers and hyphens" }, allow_nil: true
  validate :page_key_is_free, if: -> { page_key.present? && page_key_changed? }
  before_save :keep_old_page_key, if: :page_key_changed?

  before_validation { self.organization ||= production&.organization }

  # The production whose ticket page is, or used to be, at this address.
  def self.production_at(organization, key)
    where(organization_id: organization.id).find_by(page_key: key)&.production
  end

  def self.production_once_at(organization, key)
    where(organization_id: organization.id).where("old_page_keys @> ?", [ key ].to_json).order(updated_at: :desc).first&.production
  end
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

  # "Ages 21 and over", with any note about ages after it; nil for all ages.
  def age_words
    [ AgeLimit.words(minimum_age), age_note ].compact_blank.join(" · ").presence
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

  def page_key_is_free
    taken = RESERVED_PAGE_KEYS.include?(page_key) ||
            organization.productions.where.not(id: production_id).exists?(public_key: page_key) ||
            ProductionTicketing.where(organization_id: organization_id).where.not(id: id).exists?(page_key: page_key) ||
            organization.ticket_listings.exists?(slug: page_key)
    errors.add(:base, "That address is already taken by another page.") if taken
  end

  def keep_old_page_key
    was = page_key_was
    self.old_page_keys = (Array(old_page_keys) + [ was ]).compact.uniq - [ page_key ]
  end

  def production_belongs_to_organization
    errors.add(:production, "belongs to another organization") if production && organization && production.organization_id != organization_id
  end
end

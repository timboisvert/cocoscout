# frozen_string_literal: true

# A short link: cocoscout.com/t/K7M2P. The code comes from ShortKeyService
# (like /a/, /s/ and /c/) and never changes; where it points is worked out when
# it's followed, so a renamed slug or public key never breaks a printed QR.
#
# Every production with ticketing has one canonical code, the link on its
# posters: it keeps working as dates are added, and a date is a suffix
# (/t/K7M2P/oct-10). The box office has one too. Managers add named links
# ("Poster", "Instagram bio") to see which one sells; orders remember the link
# that brought the buyer.
class ShortLink < ApplicationRecord
  KINDS = %w[canonical named].freeze
  TARGET_TYPES = %w[Production TicketingProfile].freeze
  CODE_FORMAT = /\A[A-Z0-9]{4,12}\z/

  belongs_to :organization, optional: true
  belongs_to :target, polymorphic: true, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :ticket_orders, dependent: :nullify

  normalizes :code, with: ->(c) { c.to_s.strip.upcase }
  normalizes :label, with: ->(l) { l.to_s.strip.presence }

  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :kind, inclusion: { in: KINDS }
  validates :target_type, inclusion: { in: TARGET_TYPES }, allow_nil: true
  validates :label, presence: true, if: :named?

  before_validation :assign_code, on: :create

  scope :live, -> { where(archived_at: nil) }
  scope :canonical, -> { where(kind: "canonical") }
  scope :named, -> { where(kind: "named") }

  def self.lookup(code)
    live.find_by(code: code.to_s.strip.upcase)
  end

  # The one code a production (or box office) always has.
  def self.canonical_for!(target)
    canonical.find_by(target: target) ||
      create!(target: target, kind: "canonical", organization: target.organization)
  rescue ActiveRecord::RecordNotUnique
    canonical.find_by!(target: target)
  end

  # /t/CODE/oct-10: how a date is named after a production's code.
  def self.date_suffix(show)
    show.date_and_time.strftime("%b-%-d").downcase
  end

  def canonical? = kind == "canonical"
  def named? = kind == "named"
  def archived? = archived_at.present?

  def short_path(suffix = nil)
    suffix.present? ? "/t/#{code}/#{suffix}" : "/t/#{code}"
  end

  # Where the code goes right now. suffix: a date on a production's page (a
  # listing slug, 2026-10-17, or oct-17).
  def destination_path(suffix = nil)
    routes = Rails.application.routes.url_helpers
    options = query.to_h.symbolize_keys.transform_values { |v| v.to_s.presence }.compact
    options[:date] = suffix.to_s if suffix.present?
    case target
    when Production
      routes.tickets_event_path(org: TicketingProfile.for(target.organization).slug, event: target.public_key, **options)
    when TicketingProfile
      routes.tickets_box_office_path(org: target.slug, **options)
    end
  end

  # Words for the Links page.
  def points_to
    case target
    when Production then query["date"].present? ? "#{target.name} · #{query['date']}" : target.name
    when TicketingProfile then "Box office"
    else "Nowhere"
    end
  end

  # What came through this link: paid orders, the tickets still on them, and
  # their face value (price less discount, as Ticketing::ListingStats counts
  # gross when tax is added on top).
  def stats
    orders = ticket_orders.paid_like.includes(:tickets).to_a
    tickets = orders.flat_map(&:tickets).select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    { orders: orders.size, tickets: tickets.size, cents: tickets.sum { |t| t.price_cents - t.discount_cents } }
  end

  def record_click!
    self.class.where(id: id).update_all([ "clicks_count = clicks_count + 1, last_clicked_at = ?", Time.current ])
  end

  private

  def assign_code
    self.code = ShortKeyService.generate(type: :link) if code.blank?
  end
end

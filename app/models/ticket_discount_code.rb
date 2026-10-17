# frozen_string_literal: true

# A code buyers enter at checkout: dollars or percent off, for one listing,
# every date of a production, or everything the org sells — optionally only
# some tiers. Same shape as a contract's discount codes, which copy in when a
# contract's shows are listed. Uses are counted from paid orders, never stored.
class TicketDiscountCode < ApplicationRecord
  KINDS = %w[fixed percent].freeze
  # Who sees the code beyond the organization's managers (Tim, 2026-10-17),
  # beside the ticket link on their pages: the production team and the
  # cast, the team only, or nobody. Buyers never see it unless someone
  # gives it to them.
  SHARED_WITH = %w[team_and_cast team nobody].freeze
  SHARED_WITH_LABELS = { "team_and_cast" => "Production team and cast", "team" => "Production team only", "nobody" => "Nobody" }.freeze

  belongs_to :organization
  belongs_to :ticket_listing, optional: true
  belongs_to :production, optional: true
  has_many :ticket_orders, dependent: :nullify

  normalizes :code, with: ->(c) { c.to_s.strip.upcase }

  validates :code, presence: true, length: { maximum: 40 }
  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, if: -> { kind == "fixed" }
  validates :percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: -> { kind == "percent" }
  validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :shared_with, inclusion: { in: SHARED_WITH }
  validate :one_scope

  # A code typed into a manager's form: "$ off" or "% off", an amount like
  # "5" or "$5.00" or "20%", and optionally the most uses.
  def self.attributes_from_form(raw)
    amount = raw[:amount].to_s.delete("$,%").strip
    attrs = { code: raw[:code], kind: raw[:kind].presence_in(KINDS) || "fixed", max_uses: raw[:max_uses].presence }
    attrs[:shared_with] = raw[:shared_with].presence_in(SHARED_WITH) if raw.key?(:shared_with)
    if attrs[:kind] == "percent"
      attrs[:percent] = amount.presence && BigDecimal(amount)
    else
      attrs[:amount_cents] = amount.presence && (BigDecimal(amount) * 100).round.to_i
    end
    attrs
  rescue ArgumentError
    { code: raw[:code], kind: "fixed" }
  end

  def uses_count
    ticket_orders.paid_like.count
  end

  # The codes to show the people who see a date's sales (TicketSalesAccess):
  # this date's own, its production's and the organization's, still usable,
  # and shared with them. The production team sees the ones shared with the
  # team and with everyone; the cast only the ones shared with everyone.
  def self.shared_for(listing, cast: false)
    shared(listing.organization_id, cast: cast)
      .where("ticket_listing_id = :l OR production_id = :p OR (ticket_listing_id IS NULL AND production_id IS NULL)", l: listing.id, p: listing.production_id)
      .order(:code).to_a.select(&:usable?)
  end

  # For a production's own page: its codes and the organization's.
  def self.shared_for_production(production, cast: false)
    shared(production.organization_id, cast: cast)
      .where("production_id = :p OR (ticket_listing_id IS NULL AND production_id IS NULL)", p: production.id)
      .order(:code).to_a.select(&:usable?)
  end

  def self.shared(organization_id, cast:)
    where(organization_id: organization_id, active: true, shared_with: cast ? %w[team_and_cast] : %w[team team_and_cast])
  end
  private_class_method :shared

  # "20% off", "$5.00 off"
  def off_words
    kind == "percent" ? "#{format('%g', percent)}% off" : "#{ActiveSupport::NumberHelper.number_to_currency(amount_cents.to_i / 100.0)} off"
  end

  def shared_with_words
    SHARED_WITH_LABELS.fetch(shared_with, "Nobody").downcase_first
  end

  def applies_to?(listing, tier = nil)
    return false unless listing.organization_id == organization_id
    return false if ticket_listing_id && ticket_listing_id != listing.id
    return false if production_id && production_id != listing.production_id
    return true if tier.nil? || ticket_tier_ids.blank?

    ids = ticket_tier_ids.map(&:to_i)
    ids.include?(tier.id) || (tier.source_tier_id.present? && ids.include?(tier.source_tier_id))
  end

  def usable?(at = Time.current)
    active? &&
      (starts_at.nil? || starts_at <= at) &&
      (ends_at.nil? || at < ends_at) &&
      (max_uses.nil? || uses_count < max_uses)
  end

  # What this code takes off one ticket — never more than the ticket costs.
  def discount_cents_for(price_cents)
    off = kind == "percent" ? (price_cents * percent.to_d / 100).round : amount_cents.to_i
    off.clamp(0, price_cents)
  end

  private

  def one_scope
    errors.add(:base, "A code applies to one show or one production, not both") if ticket_listing_id && production_id
  end
end

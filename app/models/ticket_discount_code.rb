# frozen_string_literal: true

# A code buyers enter at checkout: dollars or percent off, for one listing,
# every date of a production, or everything the org sells — optionally only
# some tiers. Same shape as a contract's discount codes, which copy in when a
# contract's shows are listed. Uses are counted from paid orders, never stored.
class TicketDiscountCode < ApplicationRecord
  KINDS = %w[fixed percent].freeze

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
  validate :one_scope

  def uses_count
    ticket_orders.paid_like.count
  end

  def applies_to?(listing, tier = nil)
    return false unless listing.organization_id == organization_id
    return false if ticket_listing_id && ticket_listing_id != listing.id
    return false if production_id && production_id != listing.production_id
    return true if tier.nil? || ticket_tier_ids.blank?

    ticket_tier_ids.map(&:to_i).include?(tier.id)
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

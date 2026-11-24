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
  # What Add and Edit's form sends (manage/ticketing/_code_fields).
  FORM_FIELDS = %i[code kind amount limit_uses max_uses require_minimum min_tickets shared_with].freeze
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
  validate :minimum_is_a_ticket_count
  validates :shared_with, inclusion: { in: SHARED_WITH }
  validate :one_scope

  # A code typed into a manager's form: "$ off" or "% off", an amount like
  # "5" or "$5.00" or "20%", and optionally the most uses and the minimum
  # number of tickets. The form puts each of those two numbers behind a
  # toggle (limit_uses, require_minimum): off clears the number, and on with
  # nothing typed is an error the form reports. A spreadsheet row has no
  # toggles, so there a number that's present is the limit.
  def self.attributes_from_form(raw)
    amount = raw[:amount].to_s.delete("$,%").strip
    attrs = { code: raw[:code], kind: raw[:kind].presence_in(KINDS) || "fixed",
              max_uses: number_behind_toggle(raw, :limit_uses, :max_uses),
              min_tickets: number_behind_toggle(raw, :require_minimum, :min_tickets) }
    attrs[:shared_with] = raw[:shared_with].presence_in(SHARED_WITH) if raw.key?(:shared_with)
    if attrs[:kind] == "percent"
      attrs[:percent] = amount.presence && BigDecimal(amount)
    else
      attrs[:amount_cents] = amount.presence && (BigDecimal(amount) * 100).round.to_i
    end
    attrs
  rescue ArgumentError
    # An amount that isn't a number: nothing to take off, so the code doesn't save.
    { code: raw[:code], kind: "fixed", amount_cents: nil }
  end

  def self.number_behind_toggle(raw, toggle, field)
    return raw[field].presence unless raw.key?(toggle)
    return nil unless ActiveModel::Type::Boolean.new.cast(raw[toggle])

    raw[field].presence || 0
  end
  private_class_method :number_behind_toggle

  def uses_count
    ticket_orders.paid_like.count
  end

  # The codes to show the people who see a date's sales (TicketSalesAccess):
  # this date's own, its production's and the organization's, still usable,
  # and shared with them. The production team sees the ones shared with the
  # team and with everyone; the cast only the ones shared with everyone.
  def self.shared_for(listing, cast: false)
    scope = shared(listing.organization_id, cast: cast)
    scope = if listing.own_codes?
      scope.where("ticket_listing_id = :l OR (ticket_listing_id IS NULL AND production_id IS NULL)", l: listing.id)
    else
      scope.where("ticket_listing_id = :l OR production_id = :p OR (ticket_listing_id IS NULL AND production_id IS NULL)", l: listing.id, p: listing.production_id)
    end
    scope.order(:code).to_a.select(&:usable?)
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

  # The amount as a manager types it into the form: "20" or "5.00".
  def amount_words
    kind == "percent" ? format("%g", percent) : format("%.2f", amount_cents.to_i / 100.0)
  end

  def shared_with_words
    SHARED_WITH_LABELS.fetch(shared_with, "Nobody").downcase_first
  end

  def applies_to?(listing, tier = nil)
    return false unless listing.organization_id == organization_id
    return false if ticket_listing_id && ticket_listing_id != listing.id
    # A date with its own codes (TicketListing#own_codes) doesn't take its production's.
    return false if production_id && (production_id != listing.production_id || listing.own_codes?)
    return true if tier.nil? || ticket_tier_ids.blank?

    ids = ticket_tier_ids.map(&:to_i)
    ids.include?(tier.id) || (tier.source_tier_id.present? && ids.include?(tier.source_tier_id))
  end

  # A minimum of 1 is no minimum: every order has a ticket.
  def minimum?
    min_tickets.to_i > 1
  end

  # "6 or more tickets", or nil without a minimum.
  def minimum_words
    "#{min_tickets} or more tickets" if minimum?
  end

  # "10% off", or "10% off 6 or more tickets": what a buyer is told.
  def terms_words
    [ off_words, minimum_words ].compact.join(" ")
  end

  # What the ticket page tells a buyer who applied the code: "Your code
  # GROUP10 takes 10% off an order of 6 or more tickets." ("$5.00 off each
  # ticket" for a fixed amount.)
  def buyer_sentence
    off = kind == "percent" ? off_words : "#{off_words} each ticket"
    order = "#{'on ' unless kind == 'percent'}an order of #{minimum_words}" if minimum?
    "Your code #{code} takes #{[ off, order ].compact.join(' ')}."
  end

  # How many of an order's tickets count toward the minimum: the people
  # admitted on the ticket types this code takes money off (a table for four
  # is four). requests: { tier => purchases }, as TicketCheckout has them.
  def tickets_counted(listing, requests)
    requests.sum { |tier, count| applies_to?(listing, tier) ? count.to_i * tier.admits.to_i.clamp(1, 20) : 0 }
  end

  def minimum_met?(listing, requests)
    !minimum? || tickets_counted(listing, requests) >= min_tickets
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

  def minimum_is_a_ticket_count
    return if min_tickets.nil?
    return if min_tickets_before_type_cast.to_s.match?(/\A\s*[1-9]\d*\s*\z/)

    errors.add(:base, "Enter the minimum number of tickets, 1 or more")
  end

  def one_scope
    errors.add(:base, "A code applies to one show or one production, not both") if ticket_listing_id && production_id
  end
end

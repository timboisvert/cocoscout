# frozen_string_literal: true

# A deal on another show (Tim, 2026-10-05): "You're buying Boylesque; add
# tonight's Laugh Along Live for $5 off." Offered at checkout to someone
# buying the show it's for (a date, any date of a production, or anything
# the organization sells), and for a few days after they've bought. The deal
# ticket is the other show's own ticket type at the deal price, and that show
# counts the deal price.
#
# By default a buyer can add as many as the tickets they're buying: one deal
# per person. Returning the tickets that earned a deal takes the deal back
# (TicketPassRepricing), so nobody keeps a discount they didn't earn.
class TicketOffer < ApplicationRecord
  TRIGGER_SCOPES = %w[listing production any].freeze
  TARGET_SCOPES = %w[listing same_night].freeze
  DEAL_KINDS = %w[amount_off percent_off price].freeze
  # Without a number set, never more than this however many tickets.
  CEILING = 10

  belongs_to :organization
  belongs_to :trigger_listing, class_name: "TicketListing", optional: true
  belongs_to :trigger_production, class_name: "Production", optional: true
  belongs_to :target_tier, class_name: "TicketTier", optional: true
  belongs_to :target_production, class_name: "Production", optional: true
  has_many :tickets, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 80 }
  validates :trigger_scope, inclusion: { in: TRIGGER_SCOPES }
  validates :target_scope, inclusion: { in: TARGET_SCOPES }
  validates :deal_kind, inclusion: { in: DEAL_KINDS }
  validates :trigger_listing, presence: true, if: -> { trigger_scope == "listing" }
  validates :trigger_production, presence: true, if: -> { trigger_scope == "production" }
  validates :target_tier, presence: true, if: -> { target_scope == "listing" }
  validates :target_production, presence: true, if: -> { target_scope == "same_night" }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, if: -> { deal_kind == "amount_off" }
  validates :percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: -> { deal_kind == "percent_off" }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: -> { deal_kind == "price" }
  validates :max_per_order, :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :after_purchase_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 30 }
  validate :everything_is_this_organizations

  scope :live, -> { where(active: true) }

  # Offered to someone buying this date, right now?
  def triggers_on?(listing, at = Time.current)
    return false unless active? && listing.organization_id == organization_id
    return false if starts_at && at < starts_at
    return false if ends_at && at >= ends_at
    return false if max_uses && taken_count >= max_uses

    case trigger_scope
    when "listing" then trigger_listing_id == listing.id
    when "production" then trigger_production_id == listing.production_id
    else true
    end
  end

  # The date and ticket type it offers to someone buying `listing`, or nil
  # when there's nothing to offer (not on sale, the same show).
  def target_for(listing)
    tier =
      if target_scope == "listing"
        target_tier
      else
        day = listing.show.date_and_time.to_date
        other = organization.ticket_listings.joins(:show).includes(:ticket_tiers, :show)
                            .where(production_id: target_production_id, shows: { canceled: false })
                            .where(shows: { date_and_time: day.beginning_of_day..day.end_of_day }).first
        tiers = other&.ticket_tiers.to_a.select { |t| t.archived_at.nil? && !t.bundle? && !t.hidden? }
        tiers.find { |t| target_tier_name.present? && t.name.casecmp?(target_tier_name.strip) } || tiers.min_by(&:position)
      end
    return nil if tier.nil? || tier.archived_at || tier.bundle?

    target = tier.ticket_listing
    return nil if target.id == listing.id || !target.selling? || !tier.selling?

    [ target, tier ]
  end

  # One ticket's deal price.
  def deal_price_cents(tier)
    price = tier.price_cents
    case deal_kind
    when "amount_off" then [ price - amount_cents.to_i, 0 ].max
    when "percent_off" then price - (price * percent.to_d / 100).round
    else [ price_cents.to_i, price ].min
    end
  end

  # How many a buyer of `bought` tickets may add.
  def limit_for(bought)
    [ max_per_order || bought, CEILING ].min
  end

  def taken_count
    tickets.where(status: Ticket::SOLD_STATUSES).count
  end

  # "$5 off", "20% off", "$15"
  def deal_words
    case deal_kind
    when "amount_off" then "#{ActiveSupport::NumberHelper.number_to_currency(amount_cents.to_i / 100.0)} off"
    when "percent_off" then "#{percent.to_d.to_s('F').sub(/\.0\z/, '')}% off"
    else ActiveSupport::NumberHelper.number_to_currency(price_cents.to_i / 100.0)
    end
  end

  # Who it's offered to: "any date of Boylesque", "Boylesque, Oct 10", "anything".
  def buying_words
    case trigger_scope
    when "listing" then trigger_listing ? "#{trigger_listing.display_title}, #{trigger_listing.show.date_and_time.strftime('%b %-d')}" : "a date"
    when "production" then trigger_production ? "any date of #{trigger_production.name}" : "a production"
    else "anything"
    end
  end

  # What it offers: "Laugh Along Live the same night", "Laugh Along Live, Oct 10 (General)".
  def offer_words
    if target_scope == "same_night"
      "#{target_production&.name || 'another production'} the same night"
    elsif (listing = target_tier&.ticket_listing)
      "#{listing.display_title}, #{listing.show.date_and_time.strftime('%b %-d')} (#{target_tier.name})"
    else
      "another show"
    end
  end

  # The whole deal in one line, as the wizard's review and the list say it.
  def sentence
    "Anyone buying #{buying_words} gets #{offer_words} for #{deal_words}."
  end

  # A name to start from: "Boylesque → Laugh Along Live the same night".
  def suggested_name
    from = trigger_scope == "any" ? "Anything" : buying_words.delete_prefix("any date of ")
    "#{from} → #{offer_words}".truncate(80)
  end

  private

  def everything_is_this_organizations
    errors.add(:trigger_listing, "must be one of your shows") if trigger_listing && trigger_listing.organization_id != organization_id
    errors.add(:trigger_production, "must be one of your productions") if trigger_production && trigger_production.organization_id != organization_id
    errors.add(:target_tier, "must be one of your shows' ticket types") if target_tier && target_tier.ticket_listing&.organization_id != organization_id
    errors.add(:target_production, "must be one of your productions") if target_production && target_production.organization_id != organization_id
  end
end

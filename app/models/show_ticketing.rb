# frozen_string_literal: true

class ShowTicketing < ApplicationRecord
  belongs_to :show
  belongs_to :seating_configuration, optional: true

  has_many :show_ticket_tiers, -> { order(:position) }, dependent: :destroy
  has_many :ticket_listings, dependent: :destroy
  has_many :ticket_bundles, dependent: :destroy

  enum :status, {
    draft: "draft",
    active: "active",
    closed: "closed"
  }, default: :draft, prefix: true

  validates :show_id, uniqueness: true

  scope :active, -> { status_active }
  scope :for_production, ->(production) { joins(:show).where(shows: { production_id: production.id }) }

  accepts_nested_attributes_for :show_ticket_tiers, allow_destroy: true

  # Initialize from a seating configuration
  def initialize_from_configuration!(config)
    self.seating_configuration = config
    save! if new_record?
    config.duplicate_tiers_for(self)
  end

  # Copy tiers from the current seating configuration
  def copy_tiers_from_configuration!
    return unless seating_configuration

    seating_configuration.duplicate_tiers_for(self)
  end

  # Total capacity across all tiers
  def total_capacity
    show_ticket_tiers.sum(:capacity)
  end

  # Total available across all tiers
  def total_available
    show_ticket_tiers.sum(:available)
  end

  # Total sold across all tiers
  def total_sold
    show_ticket_tiers.sum(:sold)
  end

  # Total held across all tiers
  def total_held
    show_ticket_tiers.sum(:held)
  end

  # Percentage sold
  def sold_percentage
    return 0 if total_capacity.zero?

    (total_sold.to_f / total_capacity * 100).round(1)
  end

  # Active listings count
  def active_listings_count
    ticket_listings.where(status: %w[published active]).count
  end

  # Sync inventory across all listings
  def sync_all_listings!
    ticket_listings.each(&:sync!)
  end

  # Update inventory snapshot
  def update_inventory_snapshot!
    snapshot = {}
    show_ticket_tiers.each do |tier|
      snapshot[tier.id] = {
        name: tier.name,
        capacity: tier.capacity,
        available: tier.available,
        sold: tier.sold,
        held: tier.held
      }
    end
    update!(inventory_snapshot: snapshot)
  end

  # Process a sale and update inventory
  def process_sale!(tier_id, seats_sold)
    tier = show_ticket_tiers.find(tier_id)
    tier.record_sale!(seats_sold)
    update_inventory_snapshot!
    apply_sync_rules!
  end

  # Apply sync rules (this is handled at the organization level now)
  def apply_sync_rules!
    # Sync rules are now organization-level, so this is a no-op
    # Automatic sync is handled by TicketSyncJob
  end
end

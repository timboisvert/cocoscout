# frozen_string_literal: true

class TicketSyncRule < ApplicationRecord
  belongs_to :organization
  belongs_to :ticketing_provider

  enum :rule_type, {
    sync_all: "sync_all",               # Sync all events
    sync_production: "sync_production", # Sync specific production
    sync_venue: "sync_venue"            # Sync specific venue
  }, default: :sync_all, prefix: true

  validates :name, presence: true
  validates :sync_interval_minutes, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :due, -> { active.where("next_sync_at <= ?", Time.current) }

  before_validation :set_next_sync, on: :create

  # Schedule next sync
  def schedule_next_sync!
    update!(next_sync_at: Time.current + sync_interval_minutes.minutes)
  end

  # Execute sync rule
  def execute!
    return unless active?
    return unless ticketing_provider.configured?

    listings_to_sync.each(&:sync!)
    schedule_next_sync!
  end

  # Get listings matching this rule
  def listings_to_sync
    scope = ticketing_provider.ticket_listings.active

    case rule_type
    when "sync_production"
      scope.joins(show_ticketing: :show)
           .where(shows: { production_id: rule_config["production_id"] })
    when "sync_venue"
      scope.joins(show_ticketing: :show)
           .where(shows: { location_id: rule_config["location_id"] })
    else
      scope
    end
  end

  private

  def set_next_sync
    self.next_sync_at ||= Time.current
  end
end

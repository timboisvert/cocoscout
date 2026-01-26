# frozen_string_literal: true

class TicketingProductionLink < ApplicationRecord
  belongs_to :production
  belongs_to :ticketing_provider

  has_many :ticketing_show_links, dependent: :destroy
  has_many :shows, through: :ticketing_show_links

  has_one :organization, through: :ticketing_provider

  # Validations
  validates :provider_event_id, presence: true
  validates :production_id, uniqueness: {
    scope: :ticketing_provider_id,
    message: "is already linked to this provider"
  }

  # Scopes
  scope :enabled, -> { where(sync_enabled: true) }
  scope :with_ticket_sales, -> { where(sync_ticket_sales: true) }

  # Check if sync is enabled (both at link and provider level)
  def sync_enabled?
    sync_enabled && ticketing_provider.auto_sync_enabled?
  end

  # Check if this link is healthy for syncing
  def can_sync?
    sync_enabled? && ticketing_provider.healthy? && ticketing_provider.has_credentials?
  end

  # Get unlinked shows for this production
  def unlinked_shows
    production.shows.where.not(id: ticketing_show_links.select(:show_id))
  end

  # Get the provider service
  def service
    ticketing_provider.service
  end

  # Link to provider dashboard for this event
  def provider_dashboard_url
    provider_event_url.presence || service.event_dashboard_url(provider_event_id)
  end

  # Returns the provider_event_url only if it has a safe scheme (http/https)
  def safe_provider_event_url
    return nil if provider_event_url.blank?

    uri = URI.parse(provider_event_url)
    %w[http https].include?(uri.scheme) ? provider_event_url : nil
  rescue URI::InvalidURIError
    nil
  end
end

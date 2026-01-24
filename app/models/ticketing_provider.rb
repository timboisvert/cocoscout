# frozen_string_literal: true

class TicketingProvider < ApplicationRecord
  belongs_to :organization

  has_many :ticketing_production_links, dependent: :destroy
  has_many :productions, through: :ticketing_production_links
  has_many :ticketing_sync_logs, dependent: :destroy
  has_many :ticketing_pending_events, dependent: :destroy

  # Aliases for cleaner access to credential columns
  def access_token
    access_token_ciphertext
  end

  def access_token=(value)
    self.access_token_ciphertext = value
  end

  def refresh_token
    refresh_token_ciphertext
  end

  def refresh_token=(value)
    self.refresh_token_ciphertext = value
  end

  def api_key
    api_key_ciphertext
  end

  def api_key=(value)
    self.api_key_ciphertext = value
  end

  # Provider types
  PROVIDER_TYPES = %w[
    ticket_tailor
    eventbrite
    wix
    seat_engine
    square
  ].freeze

  # Sync statuses
  SYNC_STATUSES = %w[success partial failed].freeze

  # Validations
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :name, presence: true
  validates :organization_id, uniqueness: {
    scope: :provider_account_id,
    message: "already has this provider account connected",
    allow_nil: true
  }

  # Scopes
  scope :enabled, -> { where(auto_sync_enabled: true) }
  scope :healthy, -> { where("consecutive_failures < 5") }
  scope :needs_sync, -> {
    enabled.healthy.where(
      "last_synced_at IS NULL OR last_synced_at < NOW() - (sync_interval_minutes || ' minutes')::interval"
    )
  }

  # Get the service instance for this provider
  def service
    @service ||= Ticketing::ServiceFactory.build(self)
  end

  # Check if token needs refresh
  def needs_token_refresh?
    return false if token_expires_at.blank?

    token_expires_at < 5.minutes.from_now
  end

  # Check if provider has valid credentials
  def has_credentials?
    access_token.present? || api_key.present?
  end

  # Check if provider is healthy (not too many failures)
  def healthy?
    consecutive_failures < 5
  end

  # Mark sync as successful
  def mark_sync_success!
    update!(
      last_synced_at: Time.current,
      last_sync_status: "success",
      last_sync_error: nil,
      consecutive_failures: 0
    )
  end

  # Mark sync as failed
  def mark_sync_failure!(error)
    update!(
      last_synced_at: Time.current,
      last_sync_status: "failed",
      last_sync_error: error.to_s.truncate(1000),
      consecutive_failures: consecutive_failures + 1
    )
  end

  # Human-readable provider name
  def provider_display_name
    Ticketing::ServiceFactory.provider_display_name(provider_type)
  end
end

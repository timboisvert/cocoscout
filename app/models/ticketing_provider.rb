# frozen_string_literal: true

class TicketingProvider < ApplicationRecord
  belongs_to :organization

  has_many :ticket_listings, dependent: :restrict_with_error
  has_many :ticket_sync_rules, dependent: :destroy
  has_many :webhook_logs, dependent: :destroy

  # Provider types - add more as we integrate new platforms
  PROVIDER_TYPES = %w[eventbrite ticket_tailor manual].freeze

  # Capability keys that adapters can declare
  CAPABILITY_KEYS = %w[
    api_create_event
    api_update_event
    api_sync_inventory
    api_fetch_sales
    webhook_sales
    webhook_inventory
    webhook_event_updates
    requires_approval
    supports_draft
  ].freeze

  enum :status, {
    active: "active",
    inactive: "inactive"
  }, default: :active, prefix: true

  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :name, presence: true
  validates :webhook_endpoint_token, uniqueness: true, allow_nil: true

  before_create :generate_webhook_token

  scope :active, -> { status_active }
  scope :by_type, ->(type) { where(provider_type: type) }
  scope :with_valid_credentials, -> { where(credentials_valid: true) }
  scope :needing_reauth, -> { where(credentials_valid: false) }
  scope :api_enabled, -> { where(manual_only: false) }
  scope :manual_only, -> { where(manual_only: true) }
  scope :not_rate_limited, -> { where("rate_limited_until IS NULL OR rate_limited_until < ?", Time.current) }

  # Encrypt credentials (API keys, secrets)
  encrypts :encrypted_credentials

  # ============================================
  # Credential Management
  # ============================================

  def credentials
    return {} if encrypted_credentials.blank?

    JSON.parse(encrypted_credentials)
  rescue JSON::ParserError
    {}
  end

  def credentials=(hash)
    self.encrypted_credentials = hash.to_json
  end

  def api_key
    credentials["api_key"]
  end

  def api_key=(value)
    new_creds = credentials.dup
    new_creds["api_key"] = value if value.present?
    self.credentials = new_creds
  end

  def api_secret
    credentials["api_secret"]
  end

  def api_secret=(value)
    new_creds = credentials.dup
    new_creds["api_secret"] = value if value.present?
    self.credentials = new_creds
  end

  def webhook_secret
    credentials["webhook_secret"]
  end

  def webhook_secret=(value)
    new_creds = credentials.dup
    new_creds["webhook_secret"] = value if value.present?
    self.credentials = new_creds
  end

  # ============================================
  # Configuration & Status
  # ============================================

  def display_name
    "#{name} (#{provider_type.titleize})"
  end

  # Check if provider is configured and ready to use
  def configured?
    return true if manual_only?
    api_key.present?
  end

  # Check if credentials are healthy
  def credentials_healthy?
    return true if manual_only?
    credentials_valid? && !credentials_expired?
  end

  def credentials_expired?
    return false if credentials_expires_at.nil?
    credentials_expires_at < Time.current
  end

  # Check if we're currently rate limited
  def rate_limited?
    rate_limited_until.present? && rate_limited_until > Time.current
  end

  # Record a rate limit hit
  def record_rate_limit!(resets_at: nil, remaining: 0)
    update!(
      rate_limited_until: resets_at || 1.minute.from_now,
      rate_limit_resets_at: resets_at,
      rate_limit_remaining: remaining
    )
  end

  # Clear rate limit
  def clear_rate_limit!
    update!(
      rate_limited_until: nil,
      rate_limit_remaining: nil,
      rate_limit_resets_at: nil
    )
  end

  # Update rate limit info from API response headers
  def update_rate_limit_from_headers(remaining:, resets_at:)
    update!(
      rate_limit_remaining: remaining,
      rate_limit_resets_at: resets_at,
      rate_limited_until: remaining.to_i <= 0 ? resets_at : nil
    )
  end

  # ============================================
  # Capability Management
  # ============================================

  # Get merged capabilities (adapter defaults + stored overrides)
  def effective_capabilities
    adapter_caps = adapter&.capabilities || {}
    stored_caps = capabilities || {}
    adapter_caps.merge(stored_caps)
  end

  def can?(capability)
    effective_capabilities[capability.to_s] == true
  end

  def api_enabled?
    !manual_only? && can?(:api_create_event)
  end

  def supports_webhooks?
    can?(:webhook_sales) || can?(:webhook_inventory)
  end

  def requires_approval?
    can?(:requires_approval)
  end

  # ============================================
  # Webhook Management
  # ============================================

  def webhook_url
    return nil unless webhook_endpoint_token.present?
    Rails.application.routes.url_helpers.ticketing_webhook_url(
      provider_type: provider_type,
      token: webhook_endpoint_token,
      host: Rails.application.config.action_mailer.default_url_options[:host]
    )
  end

  def regenerate_webhook_token!
    update!(webhook_endpoint_token: SecureRandom.urlsafe_base64(32))
  end

  # ============================================
  # Credential Validation
  # ============================================

  def validate_credentials!
    return mark_credentials_valid! if manual_only?

    result = test_connection
    if result[:success]
      mark_credentials_valid!
    else
      mark_credentials_invalid!(result[:error])
    end
    result
  end

  def mark_credentials_valid!
    update!(
      credentials_valid: true,
      credentials_checked_at: Time.current,
      credentials_error: nil
    )
  end

  def mark_credentials_invalid!(error_message = nil)
    update!(
      credentials_valid: false,
      credentials_checked_at: Time.current,
      credentials_error: error_message
    )
  end

  # ============================================
  # Adapter
  # ============================================

  # Get the adapter class for this provider
  def adapter
    case provider_type
    when "eventbrite"
      TicketingAdapters::EventbriteAdapter.new(self)
    when "ticket_tailor"
      TicketingAdapters::TicketTailorAdapter.new(self)
    when "manual"
      TicketingAdapters::ManualAdapter.new(self)
    else
      raise "Unknown provider type: #{provider_type}"
    end
  end

  # Test the connection to this provider
  def test_connection
    return { success: true, message: "Manual provider - no connection needed" } if manual_only?
    return { success: false, error: "Not configured" } unless configured?

    adapter.test_connection
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # ============================================
  # Sync Operations
  # ============================================

  # Check if we can perform API operations right now
  def can_sync?
    return false unless status_active?
    return false unless configured?
    return false if rate_limited?
    return true if manual_only?
    credentials_healthy?
  end

  # Get all listings that need attention
  def listings_needing_sync
    ticket_listings
      .joins(:show_ticketing)
      .where("ticket_listings.next_sync_at <= ? OR ticket_listings.next_sync_at IS NULL", Time.current)
      .where.not(status: %w[ended])
  end

  private

  def generate_webhook_token
    self.webhook_endpoint_token ||= SecureRandom.urlsafe_base64(32)
  end
end

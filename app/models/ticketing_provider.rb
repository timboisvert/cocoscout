# frozen_string_literal: true

class TicketingProvider < ApplicationRecord
  belongs_to :organization

  has_many :ticket_listings, dependent: :restrict_with_error
  has_many :ticket_sync_rules, dependent: :destroy

  # Provider types - add more as we integrate new platforms
  PROVIDER_TYPES = %w[eventbrite ticket_tailor].freeze

  enum :status, {
    active: "active",
    inactive: "inactive"
  }, default: :active, prefix: true

  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :name, presence: true

  scope :active, -> { status_active }
  scope :by_type, ->(type) { where(provider_type: type) }

  # Encrypt credentials (API keys, secrets)
  encrypts :encrypted_credentials

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

  def display_name
    "#{name} (#{provider_type.titleize})"
  end

  # Check if provider is configured and ready to use
  def configured?
    api_key.present?
  end

  # Get the adapter class for this provider
  def adapter
    case provider_type
    when "eventbrite"
      TicketingAdapters::EventbriteAdapter.new(self)
    when "ticket_tailor"
      TicketingAdapters::TicketTailorAdapter.new(self)
    else
      raise "Unknown provider type: #{provider_type}"
    end
  end

  # Test the connection to this provider
  def test_connection
    return { success: false, error: "Not configured" } unless configured?

    adapter.test_connection
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

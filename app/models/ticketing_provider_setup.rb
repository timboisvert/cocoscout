# frozen_string_literal: true

# TicketingProviderSetup represents the configuration for a specific provider
# within a ProductionTicketingSetup. Each production setup can use multiple
# providers with provider-specific settings.
class TicketingProviderSetup < ApplicationRecord
  belongs_to :production_ticketing_setup
  belongs_to :ticketing_provider

  # Provider-specific image (optional override)
  has_one_attached :custom_image

  # ============================================
  # Validations
  # ============================================

  validates :ticketing_provider_id, uniqueness: { scope: :production_ticketing_setup_id }

  # ============================================
  # Scopes
  # ============================================

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :with_remote_series, -> { where.not(remote_event_series_id: nil) }

  # ============================================
  # Delegation
  # ============================================

  delegate :provider_type, :name, :adapter, :capabilities, to: :ticketing_provider
  delegate :production, :organization, :shows_to_list, to: :production_ticketing_setup

  # ============================================
  # Provider-Specific Settings
  # ============================================

  # Get a provider setting with a default
  def setting(key, default = nil)
    provider_settings&.dig(key.to_s) || default
  end

  # Set a provider setting
  def set_setting(key, value)
    self.provider_settings ||= {}
    self.provider_settings[key.to_s] = value
  end

  # Eventbrite-specific
  def eventbrite_category_id
    setting("category_id")
  end

  def eventbrite_format_id
    setting("format_id")
  end

  def eventbrite_organizer_id
    setting("organizer_id")
  end

  def eventbrite_listed?
    setting("listed", true)
  end

  # Ticket Tailor-specific
  def ticket_tailor_access_code
    setting("access_code")
  end

  def ticket_tailor_waitlist_active?
    setting("waitlist_active", false)
  end

  def ticket_tailor_box_office_slug
    setting("box_office_slug")
  end

  # ============================================
  # Grouping Strategy Support
  # ============================================

  # Does this provider support recurring/grouped events?
  def supports_recurring_events?
    capabilities["supports_recurring"] == true
  end

  # For recurring event mode: do we have a parent event created?
  def has_remote_series?
    remote_event_series_id.present?
  end

  # ============================================
  # Sync Helpers
  # ============================================

  # Shows that this provider setup should have listed
  def shows_to_sync
    production_ticketing_setup.shows_to_list_on_provider(ticketing_provider)
  end

  # Remote events that exist for this provider setup
  def remote_events
    RemoteTicketingEvent.where(
      ticketing_provider: ticketing_provider,
      production_ticketing_setup: production_ticketing_setup
    )
  end

  # Get the effective title for events on this provider
  def effective_title(show = nil)
    custom_title.presence || production_ticketing_setup.build_title(show)
  end

  # Get the effective description for events on this provider
  def effective_description
    custom_description.presence || production_ticketing_setup.description
  end

  # Get the image to use for this provider
  def image_variant
    if custom_image.attached?
      resize_for_provider(custom_image)
    else
      production_ticketing_setup.image_for_provider(ticketing_provider)
    end
  end

  private

  def resize_for_provider(image)
    case provider_type
    when "eventbrite"
      image.variant(resize_to_fill: [ 2160, 1080 ])
    when "ticket_tailor"
      image.variant(resize_to_fill: [ 1200, 630 ])
    else
      image
    end
  end
end

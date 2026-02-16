# frozen_string_literal: true

# ProductionTicketingSetup defines the rules for how a production's shows
# should be listed on ticketing providers. Created via a setup wizard.
#
# This implements "opt-out" rather than "opt-in" ticketing:
# - By default, all shows in a production get listed on all enabled providers
# - Shows can be explicitly excluded or have their settings overridden
# - The system compares these rules against what actually exists (RemoteTicketingEvent)
#   and surfaces discrepancies as issues to resolve
class ProductionTicketingSetup < ApplicationRecord
  belongs_to :production
  belongs_to :organization
  belongs_to :created_by, class_name: "Person", optional: true

  has_many :provider_setups, class_name: "TicketingProviderSetup", dependent: :destroy
  has_many :ticketing_providers, through: :provider_setups
  has_many :show_ticketing_rules, dependent: :destroy
  has_many :remote_ticketing_events, dependent: :nullify

  # Master image that gets resized for each provider
  has_one_attached :master_image
  # Provider-specific image overrides (optional)
  has_many_attached :provider_images

  # ============================================
  # Enums
  # ============================================

  enum :listing_mode, {
    all_shows: "all_shows",
    future_only: "future_only",
    selected_shows: "selected_shows"
  }, prefix: true

  enum :grouping_strategy, {
    individual_events: "individual_events",
    recurring_event: "recurring_event"
  }, prefix: true

  enum :status, {
    draft: "draft",
    active: "active",
    paused: "paused",
    archived: "archived"
  }, prefix: true

  # ============================================
  # Validations
  # ============================================

  validates :production, presence: true, uniqueness: true
  validates :listing_mode, presence: true
  validates :grouping_strategy, presence: true
  validates :status, presence: true
  validates :currency, presence: true
  validates :timezone, presence: true

  # ============================================
  # Scopes
  # ============================================

  scope :active_setups, -> { where(status: :active) }
  scope :needs_sync, -> { active_setups.where("updated_at > ?", 5.minutes.ago) }

  # ============================================
  # Status Transitions
  # ============================================

  def activate!
    return false unless status_draft? || status_paused?

    update!(
      status: :active,
      activated_at: Time.current,
      paused_at: nil
    )
    schedule_initial_sync!
    true
  end

  def pause!
    return false unless status_active?

    update!(
      status: :paused,
      paused_at: Time.current
    )
    true
  end

  def resume!
    return false unless status_paused?

    update!(
      status: :active,
      paused_at: nil
    )
    schedule_sync!
    true
  end

  def archive!
    return false if status_archived?

    transaction do
      # Mark all remote events as orphaned (they'll need cleanup)
      remote_ticketing_events.update_all(sync_status: "orphaned")

      update!(
        status: :archived,
        archived_at: Time.current
      )
    end
    true
  end

  # ============================================
  # Show Selection Logic
  # ============================================

  # Returns all shows that SHOULD be listed according to our rules
  def shows_to_list
    base_shows = case listing_mode
    when "all_shows"
      production.shows
    when "future_only"
      production.shows.where("date_and_time >= ?", activated_at || created_at)
    when "selected_shows"
      # Only shows with explicit "include" rules
      production.shows.where(
        id: show_ticketing_rules.where(rule_type: "include").select(:show_id)
      )
    end

    # Exclude shows with "exclude" rules
    excluded_show_ids = show_ticketing_rules.where(rule_type: "exclude").pluck(:show_id)
    base_shows.where.not(id: excluded_show_ids).where.not(canceled: true)
  end

  # Returns shows that SHOULD be listed on a specific provider
  def shows_to_list_on_provider(ticketing_provider)
    provider_setup = provider_setups.find_by(ticketing_provider: ticketing_provider)
    return Show.none unless provider_setup&.enabled?

    shows_to_list.reject do |show|
      rule = show_ticketing_rules.find_by(show: show)
      next false unless rule

      # Check if this provider is explicitly excluded for this show
      if rule.applies_to_provider_ids.present?
        !rule.applies_to_provider_ids.include?(ticketing_provider.id)
      else
        false
      end
    end
  end

  # Check if a specific show should be listed on a specific provider
  def should_list?(show, ticketing_provider)
    return false unless status_active?
    return false unless shows_to_list.include?(show)

    provider_setup = provider_setups.find_by(ticketing_provider: ticketing_provider)
    return false unless provider_setup&.enabled?

    rule = show_ticketing_rules.find_by(show: show)
    if rule&.applies_to_provider_ids.present?
      rule.applies_to_provider_ids.include?(ticketing_provider.id)
    else
      true
    end
  end

  # ============================================
  # Event Data Building
  # ============================================

  # Build the event data for a show, applying defaults and overrides
  def event_data_for(show)
    rule = show_ticketing_rules.find_by(show: show, rule_type: "override")
    overrides = rule&.override_data&.with_indifferent_access || {}

    {
      title: build_title(show, overrides),
      description: overrides[:description] || description || production.description,
      short_description: overrides[:short_description] || short_description,
      venue: build_venue_data(show),
      start_time: show.date_and_time,
      end_time: show.end_time || show.date_and_time + 2.hours,
      timezone: timezone,
      currency: currency,
      online_event: online_event || show.online?,
      pricing_tiers: overrides[:pricing_tiers] || default_pricing_tiers
    }
  end

  def build_title(show, overrides = {})
    return overrides[:title] if overrides[:title].present?
    return title_template.gsub("{production_name}", production.name)
                         .gsub("{show_date}", show.date_and_time.strftime("%B %d, %Y"))
                         .gsub("{show_time}", show.date_and_time.strftime("%I:%M %p")) if title_template.present?

    show.display_name
  end

  def build_venue_data(show)
    # Use show's location if available, otherwise use defaults
    if show.location.present? && !online_event
      {
        name: show.location.name,
        address: show.location.address,
        city: show.location.city,
        postal_code: show.location.postal_code,
        country: show.location.country || "US"
      }
    elsif default_venue_name.present?
      {
        name: default_venue_name,
        address: default_venue_address,
        city: default_venue_city,
        postal_code: default_venue_postal_code,
        country: default_venue_country
      }
    else
      nil
    end
  end

  # ============================================
  # Image Handling
  # ============================================

  # Get the appropriate image for a provider (resized appropriately)
  def image_for_provider(ticketing_provider)
    # Check for provider-specific override first
    provider_image = provider_images.find { |img| img.filename.to_s.start_with?("#{ticketing_provider.provider_type}_") }
    return provider_image if provider_image.present?

    # Fall back to master image, resized for provider
    return nil unless master_image.attached?

    case ticketing_provider.provider_type
    when "eventbrite"
      # Eventbrite: 2160x1080 (2:1 ratio)
      master_image.variant(resize_to_fill: [ 2160, 1080 ])
    when "ticket_tailor"
      # Ticket Tailor: 1200x630 (roughly 1.9:1)
      master_image.variant(resize_to_fill: [ 1200, 630 ])
    else
      master_image
    end
  end

  # ============================================
  # Sync Management
  # ============================================

  def schedule_initial_sync!
    provider_setups.enabled.each do |provider_setup|
      TicketingSetupSyncJob.perform_later(id, provider_setup.ticketing_provider_id)
    end
  end

  def schedule_sync!
    TicketingSetupSyncJob.perform_later(id)
  end

  # Calculate what's out of sync
  def sync_status_summary
    enabled_providers = provider_setups.enabled.includes(:ticketing_provider).map(&:ticketing_provider)

    summary = {
      missing: [],      # Shows that should be listed but aren't
      orphaned: [],     # Remote events that shouldn't exist
      outdated: [],     # Remote events that need updating
      synced: []        # Everything in sync
    }

    enabled_providers.each do |provider|
      should_exist = shows_to_list_on_provider(provider).to_a
      does_exist = remote_ticketing_events.where(ticketing_provider: provider).includes(:show)

      existing_show_ids = does_exist.map(&:show_id).compact

      # Missing: should exist but doesn't
      should_exist.each do |show|
        unless existing_show_ids.include?(show.id)
          summary[:missing] << { show: show, provider: provider }
        end
      end

      # Orphaned: exists but shouldn't
      does_exist.each do |remote_event|
        next if remote_event.show.nil? # Parent event for recurring, skip

        unless should_exist.map(&:id).include?(remote_event.show_id)
          summary[:orphaned] << remote_event
        end
      end

      # Check for outdated
      does_exist.each do |remote_event|
        next unless remote_event.show.present?

        if remote_event.needs_update?(event_data_for(remote_event.show))
          summary[:outdated] << remote_event
        else
          summary[:synced] << remote_event
        end
      end
    end

    summary
  end

  # ============================================
  # Provider Requirements
  # ============================================

  # Check what's missing to complete setup for a provider
  def missing_requirements_for(ticketing_provider)
    missing = []
    adapter = ticketing_provider.adapter

    # Check provider-specific capabilities affect what we can do
    capabilities = adapter.class::CAPABILITIES

    # Basic required fields
    missing << "description" if description.blank?

    # Venue required unless online
    unless online_event
      missing << "venue" if default_venue_name.blank? && production.shows.none? { |s| s.location.present? }
    end

    # Pricing required
    missing << "pricing_tiers" if default_pricing_tiers.empty?

    # Provider-specific requirements
    case ticketing_provider.provider_type
    when "eventbrite"
      # Eventbrite doesn't strictly require much
    when "ticket_tailor"
      # Ticket Tailor needs currency
      missing << "currency" if currency.blank?
    end

    missing
  end

  def ready_for_provider?(ticketing_provider)
    missing_requirements_for(ticketing_provider).empty?
  end
end

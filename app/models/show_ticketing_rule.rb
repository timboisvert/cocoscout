# frozen_string_literal: true

# ShowTicketingRule defines per-show exceptions to the production's
# default ticketing setup. Rules can:
#
# - Exclude: Don't list this show (remove from providers if already listed)
# - Include: Explicitly include (when listing_mode is "selected_shows")
# - Override: Use different settings for this show (different price, description, etc.)
#
# Rules can also be provider-specific using applies_to_provider_ids.
class ShowTicketingRule < ApplicationRecord
  belongs_to :production_ticketing_setup
  belongs_to :show

  # ============================================
  # Enums
  # ============================================

  enum :rule_type, {
    exclude: "exclude",
    include: "include",
    override: "override"
  }, prefix: true

  # ============================================
  # Validations
  # ============================================

  validates :show_id, uniqueness: { scope: :production_ticketing_setup_id }
  validates :rule_type, presence: true
  validate :override_data_valid, if: :rule_type_override?

  # ============================================
  # Scopes
  # ============================================

  scope :exclusions, -> { where(rule_type: :exclude) }
  scope :inclusions, -> { where(rule_type: :include) }
  scope :overrides, -> { where(rule_type: :override) }
  scope :for_provider, ->(provider) {
    where("applies_to_provider_ids IS NULL OR applies_to_provider_ids @> ?", [provider.id].to_json)
  }

  # ============================================
  # Override Data Access
  # ============================================

  # Get an override value, falling back to the setup default
  def override_value(key)
    override_data&.dig(key.to_s)
  end

  # Title override
  def override_title
    override_value("title")
  end

  # Description override
  def override_description
    override_value("description")
  end

  # Pricing tiers override (array of {name:, price_cents:, quantity:})
  def override_pricing_tiers
    override_value("pricing_tiers")
  end

  # Specific providers to list on (subset of what's enabled)
  def override_provider_ids
    override_value("provider_ids")
  end

  # ============================================
  # Provider Filtering
  # ============================================

  # Does this rule apply to a specific provider?
  def applies_to?(ticketing_provider)
    return true if applies_to_provider_ids.blank?

    applies_to_provider_ids.include?(ticketing_provider.id)
  end

  # Get the providers this rule applies to
  def applicable_providers
    return TicketingProvider.all if applies_to_provider_ids.blank?

    TicketingProvider.where(id: applies_to_provider_ids)
  end

  # ============================================
  # Convenience Methods
  # ============================================

  def exclusion?
    rule_type_exclude?
  end

  def inclusion?
    rule_type_include?
  end

  def has_overrides?
    rule_type_override? && override_data.present?
  end

  # Build the complete event data for this show, merging overrides
  def build_event_data
    return nil unless rule_type_override?

    base = production_ticketing_setup.event_data_for(show)
    base.merge(
      title: override_title || base[:title],
      description: override_description || base[:description],
      pricing_tiers: override_pricing_tiers || base[:pricing_tiers]
    )
  end

  private

  def override_data_valid
    return if override_data.blank?

    unless override_data.is_a?(Hash)
      errors.add(:override_data, "must be a hash")
      return
    end

    # Validate pricing tiers structure if present
    if override_data["pricing_tiers"].present?
      unless override_data["pricing_tiers"].is_a?(Array)
        errors.add(:override_data, "pricing_tiers must be an array")
      end
    end

    # Validate provider_ids if present
    if override_data["provider_ids"].present?
      unless override_data["provider_ids"].is_a?(Array)
        errors.add(:override_data, "provider_ids must be an array")
      end
    end
  end
end

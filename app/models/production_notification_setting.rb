# frozen_string_literal: true

class ProductionNotificationSetting < ApplicationRecord
  belongs_to :production
  belongs_to :user

  validates :user_id, uniqueness: { scope: :production_id }

  scope :enabled, -> { where(enabled: true) }

  # Ensure all org members and production team members have a setting for this production.
  # Creates missing entries with enabled=false (default off).
  def self.ensure_settings_for(production)
    organization = production.organization

    # Gather all user IDs that should have a setting
    user_ids = Set.new

    # Org owner
    user_ids << organization.owner_id if organization.owner_id

    # Org managers/viewers
    organization.organization_roles
                .where(company_role: %w[manager viewer])
                .pluck(:user_id)
                .each { |id| user_ids << id }

    # Production team members
    production.production_permissions
              .pluck(:user_id)
              .each { |id| user_ids << id }

    # Find which already have settings
    existing_ids = where(production: production).pluck(:user_id).to_set

    # Create missing ones (default disabled)
    missing_ids = user_ids - existing_ids
    return if missing_ids.empty?

    now = Time.current
    records = missing_ids.map do |uid|
      { production_id: production.id, user_id: uid, enabled: false, created_at: now, updated_at: now }
    end

    insert_all(records)
  end
end

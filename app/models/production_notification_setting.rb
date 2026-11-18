# frozen_string_literal: true

class ProductionNotificationSetting < ApplicationRecord
  belongs_to :production
  belongs_to :user

  validates :user_id, uniqueness: { scope: :production_id }

  scope :enabled, -> { where(enabled: true) }

  # Everyone who can have a switch for this production: the organization's
  # owner, its managers and viewers, and the production's own team.
  def self.team_user_ids(production)
    organization = production.organization
    ids = Set.new
    ids << organization.owner_id if organization.owner_id
    ids.merge(organization.organization_roles.where(company_role: %w[manager viewer]).pluck(:user_id))
    ids.merge(production.production_permissions.pluck(:user_id))
    ids
  end

  # The users who hear about this production: on the team today, with the
  # switch on. The ONE answer for every notice and message about a production
  # (Tim, 2026-11-11: a message to Rising Stars reached every manager in the
  # organization, switch or no switch). A switch left behind by someone who is
  # no longer on the team counts for nothing.
  #
  # whole_team_if_none: a message someone wrote has to land somewhere, so when
  # nobody has the switch on it goes to the whole team instead of to no one.
  def self.users_to_notify(production, whole_team_if_none: false)
    ensure_settings_for(production)
    team_ids = team_user_ids(production)
    ids = where(production: production, enabled: true, user_id: team_ids.to_a).pluck(:user_id)
    ids = team_ids.to_a if ids.empty? && whole_team_if_none
    User.where(id: ids).includes(:default_person).to_a
  end

  # Ensure everyone on the team has a setting for this production.
  # Creates missing entries with enabled=false (default off).
  def self.ensure_settings_for(production)
    user_ids = team_user_ids(production)

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

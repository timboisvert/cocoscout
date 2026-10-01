# frozen_string_literal: true

# Who may work the door, and how much they may do there:
#   :manager    — org managers (and superadmins): everything at the door
#   :box_office — check in, sell and comp at the door, look up orders
#   :check_in   — scan, search and check people in
# Anyone else gets nil. Grants are made in Ticketing settings → Door access.
class TicketingDoorAccess
  LEVELS = %i[check_in box_office manager].freeze

  def self.level_for(user, organization)
    return nil unless user && organization
    return :manager if user.superadmin? || organization.manageable_by?(user)

    grant = organization.ticketing_access_grants.active.find_by(user_id: user.id)
    grant&.access_level&.to_sym
  end

  def self.at_least?(level, needed)
    level && LEVELS.index(level) >= LEVELS.index(needed)
  end

  # Organizations whose door this user can work, with ticketing switched on
  # (a superadmin also sees pilot orgs that aren't switched on yet).
  def self.organizations_for(user)
    return [] unless user

    scope = Organization.joins(:ticketing_profile)
    unless user.superadmin?
      ids = TicketingAccessGrant.active.where(user_id: user.id).pluck(:organization_id) +
            user.organization_roles.where(company_role: "manager").pluck(:organization_id) +
            Organization.where(owner_id: user.id).pluck(:id)
      scope = scope.where(ticketing_profiles: { enabled: true }).where(id: ids.uniq)
    end
    scope.order(:name).to_a
  end
end

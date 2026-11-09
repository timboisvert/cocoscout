# frozen_string_literal: true

# What Role Call asks of a show, in one place, so Scheduling, Home and a
# production's page can't disagree (Tim, 2026-11-08: a contract show with no
# services read "Needs Booth Tech" on Home and on its production's page).
#
# A show is asked for two things:
#   needs(show)  its staffed services (its production's, its contract's and
#                its own: ShowServices), dropped ones included
#   roles(show)  the every-show roles (Staffing Settings → Role Call, "More
#                roles every show needs") at its venue
#
# A role one of the show's services carries is that service's line, never a
# second one. And a contract production's needs come from its contract: a role
# one of the organization's services carries (Booth Tech, when Booth Tech is a
# service) is asked of a contract show only when its services include that
# service. Our own productions are asked for every every-show role, as before.
#
# Excusing a show from a role (Show#staffing_coverage_exempt_role_ids) and
# who's on what are the caller's: Scheduling counts a role covered once its
# shift is full, Home names a role with no shift at all.
#
#   role_call = RoleCall.new(organization: org, shows: shows, services: org.services_available_to?(user))
class RoleCall
  def initialize(organization:, shows:, services:)
    @organization = organization
    @services = services
    @resolver = ShowServices.new(shows) if services
  end

  def services? = @services

  # The every-show roles, whatever the show.
  def every_show_roles
    @every_show_roles ||= @organization.house_roles.role_call.ordered.to_a
  end

  # The show's services someone on staff does, dropped ones included.
  def needs(show)
    return [] unless @resolver

    (@needs ||= {})[show.id] ||= @resolver.for(show).select(&:staffed?)
  end

  # The live contract booking this show, when one does.
  def contract_for(show) = @resolver&.contract_for(show)

  # The every-show roles asked of this show.
  def roles(show)
    carried = needs(show).select(&:needed?).flat_map { |need| need.service.house_roles.map(&:id) }.to_set
    from_services_only = services? && show.production&.type_third_party?
    every_show_roles.select { |role| role.location_id.nil? || role.location_id == show.location_id }
                    .reject { |role| carried.include?(role.id) }
                    .reject { |role| from_services_only && service_role_ids.include?(role.id) }
  end

  # Whether a shift is there for a show: tied to it, or (an evening shift
  # tied to none) overlapping it.
  def self.shift_for?(shift, show)
    tied = shift.covered_shows
    tied.any? ? tied.any? { |s| s.id == show.id } : (shift.starts_at < show.ends_at && shift.ends_at > show.date_and_time)
  end

  # The roles a shift does at a show: its own, plus any it also covers there.
  def self.role_ids_on(shift, show)
    [ shift.house_role_id ] + shift.shift_additional_roles.select { |r| r.show_id.nil? || r.show_id == show.id }.map(&:house_role_id)
  end

  # Whether a shift there for the show does one of the service's roles.
  def self.on_service?(shift, show, service)
    role_ids = service.house_roles.map(&:id)
    shift_for?(shift, show) && role_ids_on(shift, show).intersect?(role_ids)
  end

  private

  # Every role one of the organization's services carries.
  def service_role_ids
    @service_role_ids ||= HouseServiceRole.joins(:house_service).where(house_services: { organization_id: @organization.id })
                                          .distinct.pluck(:house_role_id).to_set
  end
end

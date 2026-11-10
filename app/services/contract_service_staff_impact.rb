# frozen_string_literal: true

# Who is scheduled to do a service that an amendment takes off a contract's
# dates (Tim, 2026-11-10: a Booth Tech person on a show that had the Booth
# Tech service). The review step lists them, the manager says so, and
# applying takes those shifts off the schedule: unlike a removed date
# (ContractDateRemovalImpact), which only says what's left to do.
#
# Read before the contract's services change: it compares the lines the
# contract has with the ones it's about to get.
#
#   impact = ContractServiceStaffImpact.new(contract, new_lines)
#   impact.removals        # shifts that come off, each with who's on it
#   impact.kept            # shifts doing the service that stay, each with why
#   impact.unschedule!     # after the manager has confirmed
#
# A shift comes off only when the removed service is all it's there for.
# It stays, and says why, when it has already started (those hours were
# worked), when it also covers another role, when it's there for another
# show too, or when its show still needs the role some other way. A show
# whose date this amendment removes or moves is left to the date steps.
class ContractServiceStaffImpact
  # One shift, with the services it was doing and who's on it. reason is
  # nil for a shift that comes off.
  Line = Struct.new(:shift, :services, :people, :reason, keyword_init: true) do
    def day = shift.starts_at.to_date
    def role = shift.role_label
    def service_names = services.map(&:name).uniq.to_sentence
  end

  attr_reader :contract, :removals, :kept

  def initialize(contract, new_lines, skip_rental_ids: [])
    @contract = contract
    @removals = []
    @kept = []
    return unless contract.organization.feature_available?(:staffing)

    read(Array(new_lines), Array(skip_rental_ids).map(&:to_i))
  end

  # Someone is on a shift that comes off: the manager has to say so first.
  def people?
    removals.any? { |line| line.people.any? }
  end

  def people_count
    removals.flat_map { |line| line.people.map(&:id) }.uniq.size
  end

  def any?
    removals.any? || kept.any?
  end

  # The shifts that come off, by day, for the review step.
  def removals_by_day
    removals.group_by(&:day).sort.to_h
  end

  def shift_ids
    removals.map { |line| line.shift.id }
  end

  # What the manager was shown: confirming an older list (someone was added
  # to a shift since) sends them back to read the new one.
  def token
    Digest::SHA256.hexdigest(removals.map { |line| [ line.shift.id, line.people.map(&:id).sort ] }.sort.to_json)[0, 20]
  end

  # Take the shifts off the schedule, as deleting them on Scheduling does:
  # everyone told about theirs gets "No longer scheduled" with that week's
  # next updates (StaffScheduleRemoval). only: the shifts confirmed earlier,
  # for an amendment applied later, when it's signed.
  def unschedule!(only: nil)
    ids = only && Array(only).map(&:to_i)
    done = removals.select { |line| ids.nil? || ids.include?(line.shift.id) }
    Shift.transaction do
      done.each do |line|
        line.shift.shift_assignments.each { |assignment| StaffScheduleRemoval.record!(assignment, shift: line.shift) }
        line.shift.destroy!
      end
    end
    done
  end

  private

  def read(new_lines, skip_rental_ids)
    shows = contract.contract_shows.where(canceled: false).includes(:production).to_a
                    .reject { |show| skip_rental_ids.include?(show.space_rental_id.to_i) }
    return if shows.empty?

    resolver = ShowServices.new(shows)
    shows = shows.select { |show| resolver.contract_for(show)&.id == contract.id }
    services = contract.organization.house_services.includes(:house_roles).select(&:staffed?)
    return if shows.empty? || services.empty?

    # { show => [service, ...] }: what each show stops getting from the contract.
    lost = shows.index_with do |show|
      day = show.date_and_time.to_date
      had = ShowServices.services_in(contract.draft_services, day, services)
      has = ShowServices.services_in(new_lines, day, services)
      (had - has).reject { |service| own_need?(show, service) }
    end.reject { |_, list| list.empty? }
    return if lost.empty?

    @resolver = resolver
    @lost = lost
    shifts_around(lost.keys).each { |shift| sort_out(shift) }
    @removals.sort_by! { |line| [ line.shift.starts_at, line.shift.id ] }
    @kept.sort_by! { |line| [ line.shift.starts_at, line.shift.id ] }
  end

  # The show asks for the service itself, whatever the contract says: its
  # production needs it at every show, or the show added (or dropped) it.
  def own_need?(show, service)
    @production_needs ||= ProductionServiceNeed.where(production_id: contract.production_id).pluck(:house_service_id).to_set
    @show_changes ||= ShowServiceChange.where(show_id: contract.contract_shows.select(:id)).pluck(:show_id, :house_service_id).to_set
    @production_needs.include?(service.id) || @show_changes.include?([ show.id, service.id ])
  end

  def shifts_around(shows)
    from = shows.map(&:date_and_time).min - 12.hours
    to = shows.map(&:ends_at).max + 12.hours
    contract.organization.shifts.where(starts_at: from..to)
            .includes(:house_role, :source, :shows, { shift_assignments: :person }, shift_additional_roles: :house_role).to_a
  end

  def sort_out(shift)
    pairs = @lost.flat_map { |show, services| services.select { |service| RoleCall.on_service?(shift, show, service) }.map { |service| [ show, service ] } }
    return if pairs.empty?

    people = shift.active_assignments.filter_map(&:person)
    line = Line.new(shift: shift, services: pairs.map(&:last).uniq, people: people)
    line.reason = reason_to_keep(shift, pairs)
    if line.reason.nil?
      @removals << line
    elsif people.any?
      @kept << line
    end
  end

  # Why a shift doing the removed service stays on the schedule, or nil.
  def reason_to_keep(shift, pairs)
    return "It has already started, so it stays as it is." if shift.starts_at <= Time.current
    return "The shift is #{shift.role_label}, so it stays." if shift.shift_additional_roles.any?

    losing = pairs.map(&:first).uniq
    there_for = shift.covered_shows.reject(&:canceled?).presence || shift.overlapping_shows
    other = there_for.reject { |show| losing.any? { |l| l.id == show.id } }.min_by(&:date_and_time)
    return "The shift is also there for #{show_words(other)}, so it stays." if other

    needed = losing.find { |show| still_asked?(show, shift.house_role) }
    "#{show_words(needed).upcase_first} still needs #{shift.house_role.name}, so the shift stays." if needed
  end

  # After the change, does the show still ask for this role: through another
  # service it keeps, or as an every-show role (a contract production is only
  # asked for those through its services: RoleCall#roles).
  def still_asked?(show, role)
    gone = @lost[show].map(&:id)
    return true if @resolver.for(show).any? { |need| need.needed? && !gone.include?(need.service.id) && need.service.house_roles.any? { |r| r.id == role.id } }

    @every_show_role_ids ||= contract.organization.house_roles.role_call.pluck(:id, :location_id).to_h
    return false unless @every_show_role_ids.key?(role.id)

    place = @every_show_role_ids[role.id]
    (place.nil? || place == show.location_id) && !show.production&.type_third_party?
  end

  def show_words(show)
    "the #{show.date_and_time.strftime('%a, %b %-d, %-l:%M %p')} #{show.event_type.to_s == 'show' ? 'show' : 'date'}"
  end
end

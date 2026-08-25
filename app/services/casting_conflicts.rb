# frozen_string_literal: true

# Detects double-bookings when casting: a member being added to a show who is
# already cast in another show anywhere in the organization at an overlapping
# time, or who has declared themselves unavailable for this show.
#
# Follows ContractBookingConflicts' shape (structured results with a
# plain-English message, the same 1-minute back-to-back buffer) but for
# people rather than rooms. A member already cast in the target show never
# conflicts — the same person doing two acts in one night is normal.
class CastingConflicts
  BUFFER = 1.minute

  Conflict = Struct.new(:kind, :message, :show_id, keyword_init: true) do
    # kind: :overlap (cast in an overlapping show) or :unavailable (declared
    # unavailable for the target show).
    def overlap? = kind == :overlap
  end

  # Conflicts for a single prospective assignment. Members already cast in the
  # target show are exempt from overlap conflicts here — moving them between
  # acts, or adding a second act the same night, is the point.
  def self.for_member(show:, assignable:)
    return [] if assignable.nil?

    new(show: show, members: [ assignable ], exempt_already_cast: true)
      .busy_map.fetch(member_key(assignable), [])
  end

  # { "Person_12" => [Conflict, ...] } for every member with at least one
  # conflict. Batched: three queries regardless of member count. No
  # already-cast exemption — this feeds the passive indicators, where "cast
  # here but double-booked elsewhere" is exactly what should show.
  def self.busy_map(show:, members:)
    new(show: show, members: members.compact.uniq).busy_map
  end

  def self.member_key(member)
    "#{member.class.name}_#{member.id}"
  end

  def initialize(show:, members:, exempt_already_cast: false)
    @show = show
    @members = members
    @exempt_already_cast = exempt_already_cast
  end

  def busy_map
    map = Hash.new { |h, k| h[k] = [] }
    overlap_conflicts(map)
    unavailability_conflicts(map)
    map.default_proc = nil
    map
  end

  private

  def overlap_conflicts(map)
    target_start, target_end = show_interval(@show)
    return if target_start.nil?

    exempt = @exempt_already_cast ? already_cast_keys : Set.new
    candidate_shows = overlapping_shows(target_start, target_end)
    return if candidate_shows.empty?

    assignments = member_ids_by_type.flat_map do |type, ids|
      ShowPersonRoleAssignment
        .where(show_id: candidate_shows.keys, assignable_type: type, assignable_id: ids)
        .select(:show_id, :assignable_type, :assignable_id)
        .distinct.to_a
    end

    assignments.each do |a|
      key = "#{a.assignable_type}_#{a.assignable_id}"
      next if exempt.include?(key)

      other = candidate_shows[a.show_id]
      map[key] << Conflict.new(kind: :overlap, show_id: other.id, message: overlap_message(other))
    end
  end

  def unavailability_conflicts(map)
    member_ids_by_type.each do |type, ids|
      ShowAvailability
        .where(show: @show, status: :unavailable, available_entity_type: type, available_entity_id: ids)
        .each do |sa|
          key = "#{sa.available_entity_type}_#{sa.available_entity_id}"
          message = "They marked themselves unavailable for this show"
          message += " — “#{sa.note}”" if sa.note.present?
          map[key] << Conflict.new(kind: :unavailable, show_id: @show.id, message: message + ".")
        end
    end
  end

  # Non-canceled shows in the organization (any production) whose interval
  # overlaps the target's, keyed by id. date_and_time is over-fetched a day
  # in both directions because end times and call times are resolved in Ruby.
  def overlapping_shows(target_start, target_end)
    Show
      .joins(:production)
      .includes(:production, :space_rental)
      .where(productions: { organization_id: @show.production.organization_id })
      .where(canceled: false)
      .where.not(id: @show.id)
      .where(date_and_time: (target_start - 1.day)..(target_end + 1.day))
      .each_with_object({}) do |other, hash|
        other_start, other_end = show_interval(other)
        next if other_start.nil?

        hash[other.id] = other if overlap?(target_start, target_end, other_start, other_end)
      end
  end

  # A member is busy from call time (when one is set) through the show's end.
  def show_interval(show)
    return [ nil, nil ] if show.date_and_time.blank?

    starts = show.call_time_enabled? && show.call_time.present? ? show.call_time : show.date_and_time
    starts = [ starts, show.date_and_time ].min
    [ starts, show.ends_at ]
  end

  def overlap?(a_start, a_end, b_start, b_end)
    a_start < (b_end - BUFFER) && a_end > (b_start + BUFFER)
  end

  def overlap_message(other)
    time = "#{other.date_and_time.strftime('%a, %b %-d')}, " \
           "#{other.date_and_time.strftime('%-l:%M %p').strip}–#{other.ends_at.strftime('%-l:%M %p').strip}"
    production = other.production
    show_label = other.display_name.presence || "another show"
    label = production && production.name != show_label ? "#{show_label} (#{production.name})" : show_label
    "They're already cast in #{label} on #{time}, which overlaps this show."
  end

  def already_cast_keys
    member_ids_by_type.flat_map do |type, ids|
      @show.show_person_role_assignments
           .where(assignable_type: type, assignable_id: ids)
           .distinct.pluck(:assignable_type, :assignable_id)
           .map { |t, id| "#{t}_#{id}" }
    end.to_set
  end

  def member_ids_by_type
    @member_ids_by_type ||= @members.group_by { |m| m.class.name }.transform_values { |ms| ms.map(&:id) }
  end
end

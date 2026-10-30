# frozen_string_literal: true

# Records a show canceled, taken away or moved (a ShowChange), with the cast
# and staff it touches, read at that moment. Called from Show's and
# SpaceRental's own callbacks, so every way a show changes (Shows & Events, a
# series, a contract's dates, the amend wizard) is covered without each one
# remembering. A change in the past, or one that touches nobody, isn't kept.
# docs/show_change_notices_plan.md (Tim, 2026-10-30).
module ShowChanges
  module_function

  def batch
    Current.show_change_batch ||= SecureRandom.uuid
  end

  def record_cancel(show)
    record(show, kind: "canceled", was_starts_at: show.date_and_time, was_ends_at: show.ends_at)
  end

  # Before the show goes, while its cast and shifts can still be found.
  def record_removal(show)
    return if show.canceled? # already off; its cancel was the change

    record(show, kind: "removed", was_starts_at: show.date_and_time, was_ends_at: show.ends_at)
  end

  def record_move(show, was_starts_at:, was_ends_at:)
    return if show.canceled?

    record(show, kind: "moved", was_starts_at: was_starts_at, was_ends_at: was_ends_at,
                 now_starts_at: show.date_and_time, now_ends_at: show.ends_at)
  end

  # Only the room's time moved (the show inside it kept its own): the staff on
  # shifts made for the booking.
  def record_booking_move(rental, was_starts_at:, was_ends_at:)
    show = Show.where(space_rental_id: rental.id, canceled: false).order(:date_and_time).first
    return unless show

    staff = staff_entries(Shift.where(source_type: "SpaceRental", source_id: rental.id).includes(:house_role, :additional_roles, shift_assignments: :person))
    save(show, kind: "moved", booking_only: true, cast: [], staff: staff,
               was_starts_at: was_starts_at, was_ends_at: was_ends_at, now_starts_at: rental.starts_at, now_ends_at: rental.ends_at)
  end

  # A show canceled again after being brought back, or brought back: its
  # waiting cancel is no longer news.
  def close_cancel(show)
    ShowChange.open.where(show_id: show.id, kind: "canceled").update_all(closed_at: Time.current)
  end

  # For shows canceled before changes were recorded (Home's "Tell them now"):
  # the change, made from the show as it stands.
  def for_canceled(show)
    ShowChange.where(show_id: show.id, kind: "canceled").order(:created_at).last ||
      record(show, kind: "canceled", was_starts_at: show.date_and_time, was_ends_at: show.ends_at, force: true)
  end

  def record(show, kind:, was_starts_at:, was_ends_at:, now_starts_at: nil, now_ends_at: nil, force: false)
    return if !force && [ was_starts_at, now_starts_at ].compact.max.to_i < Time.current.to_i

    save(show, kind: kind, cast: cast_entries(show), staff: staff_entries(shifts_for(show, kind)),
               was_starts_at: was_starts_at, was_ends_at: was_ends_at, now_starts_at: now_starts_at, now_ends_at: now_ends_at)
  end

  def save(show, kind:, cast:, staff:, booking_only: false, **times)
    return if cast.empty? && staff.empty?

    existing = ShowChange.find_by(batch: batch, show_id: show.id, kind: kind, booking_only: booking_only)
    if existing
      # Moved twice in one go: from where it was to where it ended up.
      existing.update!(now_starts_at: times[:now_starts_at], now_ends_at: times[:now_ends_at], cast: cast, staff: staff) if kind == "moved"
      return existing
    end

    production = show.production
    ShowChange.create!(
      organization: production.organization, production: production, show: show,
      contract: show.space_rental&.contract, changed_by_user: Current.user,
      batch: batch, kind: kind, booking_only: booking_only, show_label: label(show, times[:was_starts_at]),
      cast: cast, staff: staff, **times
    )
  end

  def label(show, at)
    "#{show.production.name} · #{(at || show.date_and_time).strftime('%a, %b %-d, %-l:%M %p')}"
  end

  # Who canceling these shows would notify (the cancel screen): the cast and
  # the staff of the ones still to come, each person once, with their roles,
  # dates and shifts.
  People = Data.define(:shows, :cast, :staff) do
    def none? = cast.empty? && staff.empty?
  end

  def people_for(shows)
    upcoming = shows.reject { |s| s.canceled? || s.ends_at < Time.current }
    cast = Hash.new { |h, k| h[k] = { roles: [], dates: [] } }
    staff = Hash.new { |h, k| h[k] = [] }
    upcoming.each do |show|
      cast_entries(show).each do |entry|
        cast[entry["person_id"]][:roles] |= entry["roles"]
        cast[entry["person_id"]][:dates] |= [ show.date_and_time ]
      end
      staff_entries(shifts_for(show, "canceled")).each do |entry|
        from = Time.zone.parse(entry["starts_at"])
        to = Time.zone.parse(entry["ends_at"])
        staff[entry["person_id"]] |= [ "#{entry['role']}, #{from.strftime('%a, %b %-d')}, #{from.strftime('%-l:%M')}–#{to.strftime('%-l:%M %p')}" ]
      end
    end
    people = Person.where(id: cast.keys + staff.keys).includes(profile_headshots: { image_attachment: :blob }).index_by(&:id)
    People.new(
      shows: upcoming,
      cast: cast.filter_map { |id, v| people[id] && { person: people[id], roles: v[:roles], dates: v[:dates].sort } }.sort_by { |c| c[:person].name.to_s.downcase },
      staff: staff.filter_map { |id, lines| people[id] && { person: people[id], lines: lines } }.sort_by { |c| c[:person].name.to_s.downcase }
    )
  end

  # Everyone cast on the show: people, and the members of cast groups.
  def cast_entries(show)
    roles = Hash.new { |h, k| h[k] = [] }
    show.show_person_role_assignments.includes(:role).each do |assignment|
      ids = case assignment.assignable_type
      when "Person" then [ assignment.assignable_id ]
      when "Group" then GroupMembership.where(group_id: assignment.assignable_id).pluck(:person_id)
      else []
      end
      ids.each { |id| roles[id] << assignment.role&.name }
    end
    roles.map { |id, names| { "person_id" => id, "roles" => names.compact.uniq } }
  end

  # The shifts a change to this show touches: the show's own per-show roles
  # (unless the shift still covers another live show), the booking's shifts
  # when the show is taken away, and the whole night's when it was the last
  # show left that night.
  def shifts_for(show, kind)
    organization = show.production.organization
    last_of_night = !other_live_show_that_night?(show)

    tied = Shift.where(organization: organization, source_type: "Show", source_id: show.id)
                .or(Shift.where(organization: organization, id: ShiftShow.where(show_id: show.id).select(:shift_id)))
                .includes(:house_role, :additional_roles, :source, :shows, shift_assignments: :person).to_a
    tied = tied.select do |shift|
      (shift.house_role&.show_specific? || last_of_night) &&
        shift.covered_shows.none? { |s| s.id != show.id && !s.canceled? }
    end

    booking = if kind == "removed" && show.space_rental_id
      Shift.where(organization: organization, source_type: "SpaceRental", source_id: show.space_rental_id)
           .includes(:house_role, :additional_roles, shift_assignments: :person).to_a
    else
      []
    end

    night = if last_of_night
      day = show.date_and_time.all_day
      organization.shifts.where(starts_at: day, source_type: nil)
                  .joins(:house_role).where(house_roles: { role_type: HouseRole.role_types[:house] })
                  .includes(:house_role, :additional_roles, shift_assignments: :person).to_a
    else
      []
    end

    (tied + booking + night).uniq(&:id)
  end

  def other_live_show_that_night?(show)
    Show.joins(:production)
        .where(productions: { organization_id: show.production.organization_id }, canceled: false)
        .where(date_and_time: show.date_and_time.all_day)
        .where.not(id: show.id).exists?
  end

  # Everyone still on these shifts (not who said they can't make it).
  def staff_entries(shifts)
    shifts.sort_by(&:starts_at).flat_map do |shift|
      shift.active_assignments.filter_map do |assignment|
        next unless assignment.person_id

        { "person_id" => assignment.person_id, "shift_id" => shift.id, "role" => shift.role_label,
          "starts_at" => shift.starts_at.iso8601, "ends_at" => shift.ends_at.iso8601 }
      end
    end
  end
end

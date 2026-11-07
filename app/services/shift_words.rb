# frozen_string_literal: true

# The words every staff notice uses for a shift (StaffScheduleNotices,
# ShiftVacancyNotificationService, ShowChangeNotices): its day, hours, place,
# the shows it covers, who else has been told they're on that day, and the
# link that lands on it in My Shifts. One place, so "Fri Nov 13, 6:00–11:30
# PM at The Annex" reads the same everywhere.
module ShiftWords
  module_function

  # A shift's times in its organization's clock (TimeZones), wherever the
  # words are built: a request in another zone, a job, My Shifts for someone
  # who works in two cities.
  def local(shift, time) = time.in_time_zone(shift.organization&.time_zone.presence || Time.zone)
  def starts(shift) = local(shift, shift.starts_at)
  def ends(shift) = local(shift, shift.ends_at)

  def day(time) = time.strftime("%A, %b %-d")
  def date_short(time) = time.strftime("%a %b %-d")
  def start_time(time) = time.strftime("%-l:%M %p")

  # "6:00–11:30 PM", or "9:00 PM–12:00 AM" across noon or midnight.
  def hours(from, to)
    if from.strftime("%p") == to.strftime("%p") && from.to_date == to.to_date
      "#{from.strftime("%-l:%M")}–#{to.strftime("%-l:%M %p")}"
    else
      "#{from.strftime("%-l:%M %p")}–#{to.strftime("%-l:%M %p")}"
    end
  end

  def shift_hours(shift) = hours(starts(shift), ends(shift))

  # The part of the day a shift takes, for "so you have that evening back".
  def day_part(time)
    hour = time.hour
    if hour < 12 then "morning"
    elsif hour < 17 then "afternoon"
    else "evening"
    end
  end

  # "that night" for an evening shift, "that day" otherwise.
  def that_day(time) = time.hour >= 17 ? "that night" : "that day"

  # The shows the shift covers: "That night: Rising Stars (7:30 PM)". Nil for
  # a shift with none (a booking, a standalone shift).
  def shows_line(shift)
    shows = shift.covered_shows.reject(&:canceled?)
    return nil if shows.empty?

    "#{that_day(starts(shift)).sub(/\Athat/, 'That')}: " +
      shows.map { |s| "#{s.production&.name || s.display_name} (#{start_time(local(shift, s.date_and_time))})" }.join(", ")
  end

  # Others working that day, at the same organization, whose shift overlaps
  # this one and who have been told they're on: "Mia Manager (House), Dan
  # Lee (Door)". Nobody told, nil: a name here is a promise that they know.
  def also_on(shift, person)
    rows = ShiftAssignment.active.where.not(notified_at: nil).where.not(person_id: person.id)
                          .joins(:shift).where(shifts: { organization_id: shift.organization_id })
                          .where("shifts.starts_at < ? AND shifts.ends_at > ?", shift.ends_at, shift.starts_at)
                          .includes(:person, shift: [ :house_role, :additional_roles ])
                          .sort_by { |a| [ a.shift.starts_at, a.person.name.to_s ] }
    names = rows.map { |a| "#{a.person.name} (#{a.shift.role_label})" }.uniq
    names.presence&.join(", ")
  end

  # The same, for a page of shifts in one query: { shift_id => "Mia Manager
  # (House)" }, leaving out the viewer's own people.
  def also_on_for(shifts, person_ids)
    also_on_rows_for(shifts, person_ids).transform_values do |mine|
      mine.map { |a| "#{a.person.name} (#{a.shift.role_label})" }.uniq.join(", ")
    end
  end

  # The rows behind it, for a card that names each person's role and hours:
  # { shift_id => [ShiftAssignment, ...] }, told people only, in order of
  # when they start.
  def also_on_rows_for(shifts, person_ids)
    return {} if shifts.empty?

    rows = ShiftAssignment.active.where.not(notified_at: nil).where.not(person_id: person_ids)
                          .joins(:shift).where(shifts: { organization_id: shifts.map(&:organization_id).uniq })
                          .where("shifts.starts_at < ? AND shifts.ends_at > ?", shifts.map(&:ends_at).max, shifts.map(&:starts_at).min)
                          .includes(:person, shift: [ :house_role, :additional_roles, :organization ]).to_a
    shifts.each_with_object({}) do |shift, h|
      mine = rows.select { |a| a.shift.organization_id == shift.organization_id && a.shift.starts_at < shift.ends_at && a.shift.ends_at > shift.starts_at }
                 .sort_by { |a| [ a.shift.starts_at, a.person.name.to_s ] }
      h[shift.id] = mine if mine.any?
    end
  end

  def location(shift)
    shift.house_role&.location&.name.presence || shift.source.try(:location).try(:name).presence
  end

  def first_name(person)
    person.name.to_s.split(/\s+/).first.presence || person.name.to_s
  end

  # The variables the single-shift templates share.
  def variables(shift, person)
    {
      recipient_name: first_name(person),
      organization_name: shift.organization.name,
      role_label: shift.role_label,
      shift_day: day(starts(shift)),
      shift_date_short: date_short(starts(shift)),
      shift_hours: shift_hours(shift),
      start_time: start_time(starts(shift)),
      location_name: location(shift),
      shows_line: shows_line(shift),
      also_on: also_on(shift, person),
      shift_url: shift_url(shift),
      my_shifts_link: my_shifts_url
    }
  end

  # One list item for a shift: the day (linked to the shift on My Shifts),
  # hours, role and place. Everything escaped; the templates take it as HTML.
  def list_item(shift)
    e = ->(s) { ERB::Util.html_escape(s) }
    place = location(shift)
    "<li style=\"margin-bottom:6px;\">" \
      "<a href=\"#{shift_url(shift)}\"><strong>#{e.call(day(starts(shift)))}</strong></a> · " \
      "#{e.call(shift_hours(shift))} · #{e.call(shift.role_label)}#{place ? " · #{e.call(place)}" : ''}" \
    "</li>"
  end

  def shift_url(shift) = my_shifts_url(anchor: "shift-#{shift.id}")

  def my_shifts_url(**args)
    Rails.application.routes.url_helpers.my_shifts_url(**url_options, **args)
  end

  # The mailer's host and port (the links in an email are the mailer's).
  def url_options
    opts = Rails.application.config.action_mailer.default_url_options.presence || { host: "localhost", port: 3000 }
    opts.slice(:host, :port, :protocol)
  end
end

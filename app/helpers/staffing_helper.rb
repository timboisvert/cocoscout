# frozen_string_literal: true

module StaffingHelper
  # Standard ACH funding clears, then Connect payouts settle to each person's
  # bank. This window is what a manager actually cares about ("if I pay today,
  # when do they get the money?"). An estimate — weekends are skipped, holidays
  # aren't modeled.
  DEPOSIT_ESTIMATE_BUSINESS_DAYS = 2..4

  # A staff member's name with their pronouns beside it in gray —
  # "Sam Rivera (they/them)". For HTML only; plain-text places (selects,
  # emails) keep display_name.
  def staff_name_with_pronouns(member)
    pronouns = member.display_pronouns
    return member.display_name unless pronouns

    safe_join([ member.display_name, " ", tag.span("(#{pronouns})", class: "font-normal text-gray-500") ])
  end

  # The W-9 pill for a staff member: { text:, classes:, title: }, or nil when
  # there's nothing worth flagging (compact: true hides "received" and
  # "not required" — the staff list only shouts about what needs doing).
  W9_PILL_COLORS = { green: "bg-green-100 text-green-700", amber: "bg-amber-100 text-amber-700",
                     gray: "bg-gray-100 text-gray-600" }.freeze

  def w9_pill(member, compact: false)
    pill = case member.w9_status
    when :received
      { text: "W-9 received", color: :green, title: "W-9 on file." }
    when :exempt
      { text: "No W-9 needed", color: :gray, title: "Marked as not needing a W-9." }
    when :not_required
      { text: "W-9 off", color: :gray, title: "Your organization doesn't collect W-9s." }
    when :requested
      { text: "W-9 requested", color: :amber, title: "Asked #{time_ago_in_words(member.w9_requested_at)} ago — waiting on them." }
    else
      { text: "W-9 needed", color: :amber, title: "Nobody has asked for their W-9 yet." }
    end
    return nil if compact && %i[received exempt not_required].include?(member.w9_status)

    pill.merge(classes: W9_PILL_COLORS.fetch(pill[:color]))
  end

  # Add N business days to a date, skipping weekends. Holidays aren't modeled —
  # these power the estimated pay-timing display, which is explicitly an estimate.
  def add_business_days(date, count)
    date = date.to_date
    count.times do
      loop do
        date += 1
        break unless date.saturday? || date.sunday?
      end
    end
    date
  end

  # [earliest, latest] estimated deposit dates if a run is funded on `from`.
  def estimated_deposit_window(from = Date.current)
    [ add_business_days(from, DEPOSIT_ESTIMATE_BUSINESS_DAYS.first),
      add_business_days(from, DEPOSIT_ESTIMATE_BUSINESS_DAYS.last) ]
  end

  # The data every "edit shift" trigger hands the shift-edit modal about the
  # extra roles: which roles, which shows each is scoped to ([] = every show),
  # and the shows the shift covers so the modal can offer them. One helper so
  # the board, the cards and the Gantt can't drift apart.
  def shift_edit_role_attrs(shift)
    covered = shift.covered_shows
    tag.attributes(data: {
      shift_additional_role_ids: shift.additional_roles.map(&:id).uniq.to_json,
      shift_additional_role_scopes: shift.additional_role_scopes.to_json,
      shift_covered_shows: covered.map { |show| { id: show.id, label: shift_show_label(show) } }.to_json
    })
  end

  # What every "add a shift" trigger for a day hands the shift-add modal: the
  # day, the per-role default times (the same math the generator uses, so
  # adding a removed role back gets the identical window), each per-show
  # role's window for each show, and the day's shows to pick from. House roles
  # span the evening (first show's start to the last one's end), per-show roles
  # the first show; a day without shows falls back to 5 to 11 PM.
  def shift_add_data(day, day_shows, house_roles, source_show: day_shows.first)
    role_defaults = house_roles.each_with_object({}) do |role, h|
      if day_shows.any?
        starts_at = day_shows.first.date_and_time
        ends_at = (role.show_specific? ? day_shows.first : day_shows.last).ends_at
      else
        starts_at = day.in_time_zone.change(hour: 17)
        ends_at = day.in_time_zone.change(hour: 23)
      end
      h[role.id.to_s] = { starts_at: starts_at.strftime("%Y-%m-%dT%H:%M"), ends_at: ends_at.strftime("%Y-%m-%dT%H:%M") }
    end
    show_defaults = {}
    if day_shows.any?
      house_roles.select(&:show_specific?).each do |role|
        show_defaults[role.id.to_s] = day_shows.to_h do |show|
          [ show.id.to_s, { starts_at: show.date_and_time.strftime("%Y-%m-%dT%H:%M"), ends_at: show.ends_at.strftime("%Y-%m-%dT%H:%M") } ]
        end
      end
    end
    day_shows_options = day_shows.map do |s|
      { id: s.id.to_s, label: [ s.production&.name, s.date_and_time.strftime("%-l:%M %p") ].compact.join(" · ") }
    end
    {
      "day-label": day.strftime("%A, %b %-d"),
      "day-iso": day.iso8601,
      "role-defaults": role_defaults.to_json,
      "source-show-id": source_show&.id,
      "show-defaults": show_defaults.to_json,
      "day-shows": day_shows_options.to_json
    }
  end

  # A shift's hours as a one-line chip reads them: "7:30–9:45" for an evening,
  # "9:00a–5:00p" once either end is in the morning.
  def shift_compact_range(shift)
    from = shift.starts_at
    to = shift.ends_at
    if from.hour < 12 || to.hour < 12 && to.to_date == from.to_date
      "#{from.strftime('%-l:%M')}#{from.strftime('%P')[0]}–#{to.strftime('%-l:%M')}#{to.strftime('%P')[0]}"
    else
      "#{from.strftime('%-l:%M')}–#{to.strftime('%-l:%M')}"
    end
  end

  def shift_time_range(shift)
    "#{shift.starts_at.strftime('%-l:%M %p')}–#{shift.ends_at.strftime('%-l:%M %p')}"
  end

  # "Dev P." — a first name and the last initial, for a one-line chip.
  def short_person_name(person)
    first, *rest = person.name.to_s.split
    rest.any? ? "#{first} #{rest.last[0]}." : first.to_s
  end

  # How staffed a set of shifts is: slots filled of slots needed, and how many
  # people said they can't make it. Renter and not-needed shifts need nobody.
  def shift_slot_stats(shifts)
    needing = shifts.select(&:needs_assignment?)
    {
      staffed: needing.sum { |s| [ s.assigned_count, s.required_count ].min },
      total: needing.sum(&:required_count),
      declined: shifts.sum { |s| s.shift_assignments.count(&:declined?) }
    }
  end

  # How a covered show reads on a chip: "9:00 PM Improv Jam".
  def shift_show_label(show)
    [ show.date_and_time&.strftime("%-l:%M %p"), show.production&.name ].compact.join(" ")
  end

  # The extra roles as the card lists them, naming the shows when a role only
  # covers some of them: "Tech (9:00 PM)".
  def shift_additional_role_labels(shift)
    covered = shift.covered_shows
    scopes = shift.additional_role_scopes
    shift.additional_roles.uniq.map do |role|
      show_ids = scopes[role.id] || []
      next role.name if show_ids.empty? || covered.size < 2

      times = covered.select { |s| show_ids.include?(s.id) }.map { |s| s.date_and_time&.strftime("%-l:%M %p") }.compact
      "#{role.name} (#{times.join(', ')})"
    end
  end
end

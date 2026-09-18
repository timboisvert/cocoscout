# frozen_string_literal: true

module StaffingHelper
  # Standard ACH funding clears, then Connect payouts settle to each person's
  # bank. This window is what a manager actually cares about ("if I pay today,
  # when do they get the money?"). An estimate — weekends are skipped, holidays
  # aren't modeled.
  DEPOSIT_ESTIMATE_BUSINESS_DAYS = 2..4

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

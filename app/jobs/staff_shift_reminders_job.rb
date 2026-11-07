# frozen_string_literal: true

# The afternoon before a shift, a reminder: "Tomorrow: Bartender, 6:00 PM at
# The Annex", with that night's shows (plan: staffing notifications, Tim
# 2026-11-07, "do it all").
#
# Runs every hour and acts for each organization at 4 PM on its own clock.
# A row is reminded once (reminded_at, stamped before the notice is sent, so
# a rerun never sends twice), only for a shift of a published week (that's
# what My Shifts shows), only while the row stands (a declined row is a hole,
# not a shift), and only to someone with a login to be reminded through. Two
# shifts tomorrow make one notice. The words are the shift as it is now: the
# same as My Shifts, so nothing here can disagree with it.
class StaffShiftRemindersJob < ApplicationJob
  queue_as :default

  HOUR = 16

  def perform(now = Time.current, force: false)
    Organization.find_each do |organization|
      TimeZones.use(organization.time_zone.presence || TimeZones.default) do
        local = now.in_time_zone(Time.zone)
        next unless force || local.hour == HOUR

        remind(organization, local.to_date + 1)
      end
    rescue StandardError => e
      Rails.logger.error("[StaffShiftRemindersJob] org #{organization.id}: #{e.class}: #{e.message}")
    end
  end

  # The rows to remind for a day, in the current zone (the organization's).
  def self.due(organization, day)
    ShiftAssignment.active.where(reminded_at: nil)
                   .joins(:shift, person: :user)
                   .where(shifts: { organization_id: organization.id, starts_at: day.all_day })
                   .includes(:person, shift: [ :house_role, :additional_roles, :organization, :source, { shows: :production } ])
  end

  private

  def remind(organization, day)
    return unless StaffingFinalization.published?(organization, day)

    self.class.due(organization, day).to_a.group_by(&:person).each do |person, rows|
      ids = rows.map(&:id)
      next if ShiftAssignment.where(id: ids, reminded_at: nil).update_all(reminded_at: Time.current).zero?

      deliver(organization, person, rows.sort_by { |a| a.shift.starts_at })
    end
  end

  def deliver(organization, person, rows)
    shifts = rows.map(&:shift)
    first = shifts.first
    ContentTemplateService.deliver(
      template_key: "staff_shift_reminder",
      variables: {
        recipient_name: ShiftWords.first_name(person),
        organization_name: organization.name,
        shift_day: ShiftWords.day(ShiftWords.starts(first)),
        headline: headline(shifts),
        shifts_list: shifts.map { |s| list_item(s, person) }.join,
        shift_url: ShiftWords.shift_url(first),
        my_shifts_link: ShiftWords.my_shifts_url
      },
      sender: nil,
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      visibility: :personal,
      mailer_class: StaffingNoticeMailer.with(organization_id: organization.id),
      mailer_method: :notice
    )
  end

  # "Bartender, 6:00 PM at The Annex"; "Bartender at 6:00 PM, then Door at 9:00 PM".
  def headline(shifts)
    if shifts.one?
      shift = shifts.first
      place = ShiftWords.location(shift)
      "#{shift.role_label}, #{ShiftWords.start_time(ShiftWords.starts(shift))}#{place ? " at #{place}" : ''}"
    else
      shifts.map { |s| "#{s.role_label} at #{ShiftWords.start_time(ShiftWords.starts(s))}" }.join(", then ")
    end
  end

  # The hours, role and place, then the shows.
  def list_item(shift, _person)
    e = ->(s) { ERB::Util.html_escape(s) }
    place = ShiftWords.location(shift)
    lines = [ "<strong>#{e.call(ShiftWords.shift_hours(shift))}</strong> · #{e.call(shift.role_label)}#{place ? " · #{e.call(place)}" : ''}" ]
    shows = ShiftWords.shows_line(shift)
    lines << e.call(shows) if shows
    "<li style=\"margin-bottom:6px;\">#{lines.join('<br>')}</li>"
  end
end

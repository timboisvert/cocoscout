# frozen_string_literal: true

module Manage
  # The week as Scheduling and Home both read it: which week or day was asked
  # for, the organization's shows in a range, each show's cast, who can't make
  # an upcoming shift, and the dots and statuses the two-month calendar draws.
  # One place, so the two pages can't drift apart.
  module WeekLoaders
    extend ActiveSupport::Concern

    HEADSHOT_PRELOAD = { profile_headshots: { image_attachment: :blob } }.freeze

    private

    def parse_week_start(value)
      Date.parse(value.to_s).beginning_of_week
    rescue ArgumentError, TypeError
      Date.current.beginning_of_week
    end

    def parse_day(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # The organization's shows in the range, canceled ones left out unless
    # asked for (Home strikes them through; Scheduling has no use for them).
    # productions: narrow to these (Home shows what the person can see).
    def shows_in_range(range, productions: nil, canceled: false)
      scope = ::Show.joins(:production)
                    .where(productions: { organization_id: Current.organization.id })
                    .where(date_and_time: range.first.beginning_of_day..range.last.end_of_day)
      scope = scope.where(production_id: productions.map(&:id)) if productions
      scope = scope.where(canceled: [ false, nil ]) unless canceled
      scope.includes(:production, :location, :location_space, :space_rental)
           .order(:date_and_time)
           .to_a
    end

    # Which calendar day a shift belongs to on the schedule. Source-linked shifts
    # (generated from a show or rental) follow their source's day, so a show at
    # 12:00 AM whose shift starts 11:00 PM the previous evening still groups with
    # the show's day. Falls back to the shift's own start date for free-standing
    # shifts, or when the source's day lands outside the visible week.
    def staffing_day_for(shift, week_range)
      anchor = shift.source.try(:date_and_time) || shift.source.try(:starts_at)
      day = anchor&.to_date
      return day if day && week_range.cover?(day)

      shift.starts_at.to_date
    end

    # The months the two-month calendar and the phone's jump sheet can reach
    # around a week: three back, four ahead.
    def calendar_months_around(week_start)
      (-3..4).map { |i| week_start.beginning_of_month + i.months }
    end

    # Dates with a show on them, for the calendar dots.
    def calendar_show_dates(from, to, productions: nil)
      scope = ::Show.joins(:production)
                    .where(productions: { organization_id: Current.organization.id })
                    .where(date_and_time: from.beginning_of_day..to.end_of_day)
                    .where(canceled: [ false, nil ])
      scope = scope.where(production_id: productions.map(&:id)) if productions
      scope.pluck(:date_and_time)
            .map { |t| t.in_time_zone.to_date }
            .to_set
    end

    # { week_start => :open | :draft | :published } for every week with a
    # shift: open when a shift still needs someone, else published or draft.
    def calendar_week_statuses(from, to)
      shifts = Current.organization.shifts
                      .where(starts_at: from.beginning_of_day..to.end_of_day)
                      .pluck(:id, :starts_at, :required_count, :coverage_mode)
      return {} if shifts.empty?

      assigned = ShiftAssignment.active.where(shift_id: shifts.map(&:first)).group(:shift_id).count
      published = Current.organization.staffing_finalizations
                         .where(week_start: from..to).where.not(finalized_at: nil)
                         .pluck(:week_start).to_set
      shifts.group_by { |_id, starts_at, _req, _mode| starts_at.in_time_zone.to_date.beginning_of_week }
            .transform_values do |rows|
              open = rows.any? { |id, _s, required, mode| mode == "needs_assignment" && assigned.fetch(id, 0) < required }
              open ? :open : nil
            end
            .to_h { |week, status| [ week, status || (published.include?(week) ? :published : :draft) ] }
    end

    # Staff who declined ("can't make it") an upcoming shift for this org.
    def declined_upcoming_assignments
      ShiftAssignment.declined
        .joins(:shift)
        .where(shifts: { organization_id: Current.organization.id })
        .where("shifts.ends_at >= ?", Time.current)
        .includes(shift: [ :house_role, :additional_roles, :source, :shift_assignments, { shows: :production } ], person: HEADSHOT_PRELOAD)
        .order("shifts.starts_at ASC")
        .to_a
    end

    # { show_id => [Person, ...] } — direct cast plus members of any cast groups.
    # Queries the join table directly: the Show#cast_people scope references the
    # join table by name, which breaks under eager preloading.
    def build_show_cast(shows)
      return {} if shows.empty?

      show_ids = shows.map(&:id)

      # Two passes of ids first, then one load of the people. A polymorphic
      # belongs_to can't carry nested includes, so preloading headshots through
      # :assignable isn't available — and the same person often appears on
      # several shows, so loading them once is the cheaper shape anyway.
      direct = ShowPersonRoleAssignment
        .where(show_id: show_ids, assignable_type: "Person")
        .pluck(:show_id, :assignable_id)

      group_ids_by_show = ShowPersonRoleAssignment
        .where(show_id: show_ids, assignable_type: "Group")
        .pluck(:show_id, :assignable_id)
      members_by_group = if group_ids_by_show.any?
        GroupMembership.where(group_id: group_ids_by_show.map(&:last))
                       .pluck(:group_id, :person_id)
                       .group_by(&:first)
                       .transform_values { |rows| rows.map(&:last) }
      else
        {}
      end

      person_ids = direct.map(&:last) + members_by_group.values.flatten
      people = Person.where(id: person_ids.uniq).includes(HEADSHOT_PRELOAD).index_by(&:id)

      result = Hash.new { |h, k| h[k] = [] }
      direct.each { |show_id, person_id| (person = people[person_id]) && result[show_id] << person }
      group_ids_by_show.each do |show_id, group_id|
        members_by_group.fetch(group_id, []).each { |pid| (person = people[pid]) && result[show_id] << person }
      end

      result.transform_values(&:uniq)
    end
  end
end

# frozen_string_literal: true

module Manage
  # Staffing module landing page IS the weekly schedule. Sub-areas for House
  # Roles (Manage::Staffing::HouseRolesController) and Staff
  # (Manage::Staffing::StaffController) live under app/controllers/manage/staffing/.
  class StaffingController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    def index
      return unless Current.organization

      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      @shows_by_day = shows_in_range(@week_start..@week_end).group_by { |s| s.date_and_time.to_date }
      week_range = (@week_start..@week_end)
      shifts = Current.organization.shifts
        .for_week(@week_start)
        .includes(:house_role, :source, shift_assignments: :person)
        .ordered
        .to_a
      @shifts_by_day = shifts.group_by { |s| staffing_day_for(s, week_range) }

      @house_roles = Current.organization.house_roles.active.ordered.to_a
      @house_role_count = @house_roles.size
      @staff_count = Current.organization.organization_staff_members.active.count
      @staff_by_role_payload = build_staff_by_role_payload

      # Collision-detection payloads (consumed by the assign modal): the time
      # span + label of every shift this week, and which shift ids each person
      # is already on. The modal warns before double-booking someone.
      @shift_times_payload = shifts.each_with_object({}) do |s, h|
        h[s.id.to_s] = {
          starts_at: s.starts_at.iso8601,
          ends_at: s.ends_at.iso8601,
          role: s.house_role.name,
          day: s.starts_at.strftime("%a %b %-d"),
          time_range: "#{s.starts_at.strftime("%-l:%M %p")}–#{s.ends_at.strftime("%-l:%M %p")}"
        }
      end
      @person_busy_payload = shifts.each_with_object({}) do |s, h|
        s.shift_assignments.each do |a|
          (h[a.person_id.to_s] ||= []) << s.id.to_s
        end
      end

      # Staff unavailability for this week, so the assign modal can flag/filter
      # people who marked themselves unavailable on a shift's date + day part.
      staff_person_ids = Current.organization.organization_staff_members.active.pluck(:person_id)
      @staff_unavailability_payload = StaffUnavailability
        .where(person_id: staff_person_ids, date: @week_start..@week_end)
        .group_by { |u| u.person_id.to_s }
        .transform_values { |list| list.map { |u| { date: u.date.iso8601, scope: u.scope } } }
    end

    # Per-day shift auto-generation. See the long comment in the previous
    # ScheduleController for the algorithm — moved here when /staffing became
    # the schedule page itself.
    def generate
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days
      roles = Current.organization.house_roles.active.to_a
      if roles.empty?
        redirect_to manage_staffing_index_path(week_start: @week_start.to_s),
                    alert: "Add at least one house role first." and return
      end

      shows_by_day = shows_in_range(@week_start..@week_end).group_by { |s| s.date_and_time.to_date }
      created = 0
      skipped = 0

      shows_by_day.each do |_day, day_shows|
        sorted = day_shows.sort_by(&:date_and_time)
        first_show = sorted.first
        last_show = sorted.last

        roles.each do |role|
          if role.location_id.present?
            next unless sorted.any? { |s| s.location_id == role.location_id }
          end

          # Anchor to the first show's start and the LAST show's end — the end
          # offset is "minutes after the last show ends," not "minutes after it starts."
          starts_at = first_show.date_and_time + role.default_start_offset_minutes.minutes
          ends_at   = last_show.ends_at        + role.default_end_offset_minutes.minutes
          next if ends_at <= starts_at

          shift = Current.organization.shifts.new(
            house_role: role,
            source: first_show,
            starts_at: starts_at,
            ends_at: ends_at,
            required_count: role.default_required_count,
            coverage_mode: :needs_assignment
          )
          begin
            shift.save!
            created += 1
          rescue ActiveRecord::RecordNotUnique
            skipped += 1
          end
        end
      end

      notice =
        if created.zero? && skipped.zero?
          "No shows in this week — nothing to generate."
        elsif created.zero?
          "Already up to date — no new shifts needed."
        else
          "#{created} shift(s) generated#{" (#{skipped} already existed and were skipped)" if skipped > 0}."
        end
      redirect_to manage_staffing_index_path(week_start: @week_start.to_s), notice: notice
    end

    private

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

    def parse_week_start(value)
      Date.parse(value.to_s).beginning_of_week
    rescue ArgumentError, TypeError
      Date.current.beginning_of_week
    end

    def shows_in_range(range)
      ::Show.joins(:production)
            .where(productions: { organization_id: Current.organization.id })
            .where(date_and_time: range.first.beginning_of_day..range.last.end_of_day)
            .where(canceled: [ false, nil ])
            .includes(:production, :location)
            .order(:date_and_time)
            .to_a
    end

    def build_staff_by_role_payload
      quals = StaffRoleQualification
        .joins(organization_staff_member: :person)
        .where(organization_staff_members: { organization_id: Current.organization.id, archived_at: nil })
        .includes(organization_staff_member: :person)
        .order("people.name")

      quals.group_by(&:house_role_id).transform_values do |group|
        group.map do |q|
          p = q.organization_staff_member.person
          variant = p.respond_to?(:safe_headshot_variant) ? p.safe_headshot_variant(:thumb) : nil
          {
            id: p.id,
            name: p.name,
            initials: p.initials,
            headshot_url: variant ? url_for(variant) : nil
          }
        end
      end.transform_keys(&:to_s)
    end
  end
end

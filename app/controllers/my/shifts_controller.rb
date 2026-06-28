# frozen_string_literal: true

module My
  # Talent-side view of house staffing shifts the user has been assigned to
  # (the Staffing module's counterpart to "My Shows & Events"), plus the place
  # where staff mark the dates they're unavailable to work.
  class ShiftsController < ApplicationController
    SCOPES = %w[all_day day_shifts evening_shifts].freeze

    def index
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      @people_by_id = @people.index_by(&:id)
      @my_person_ids = people_ids.to_set

      @tab = params[:tab] == "all_staff" ? "all_staff" : "mine"

      assignments = ShiftAssignment
        .where(person_id: people_ids)
        .joins(:shift)
        .where("shifts.ends_at >= ?", Time.current)
        .includes(:person, shift: [ :house_role, :additional_roles, :organization, :source ])
        .order("shifts.starts_at ASC")
        .to_a

      # Drafts are hidden: a shift only shows once its org has finalized that
      # week's schedule. Keyed by (organization_id, Monday-of-week).
      finalized_weeks = StaffingFinalization.finalized.pluck(:organization_id, :week_start).to_set
      assignments.select! do |a|
        finalized_weeks.include?([ a.shift.organization_id, a.shift.starts_at.to_date.beginning_of_week ])
      end

      @rows = assignments.map { |a| { assignment: a, shift: a.shift, person: a.person } }
      @rows_by_day = @rows.group_by { |r| r[:shift].starts_at.to_date }
      @has_any = @rows.any?

      load_all_staff_calendar(people_ids, finalized_weeks) if @tab == "all_staff"

      # Unavailability for the calendar/summary (the client renders both). Cover
      # the current month through ~12 months out so month navigation has data.
      person = Current.user.person
      @unavailability_entries =
        if person
          person.staff_unavailabilities
                .where(date: Date.current.beginning_of_month..(Date.current + 12.months))
                .order(:date)
                .map { |u| { date: u.date.iso8601, scope: u.scope } }
        else
          []
        end
    end

    # Upsert/clear unavailability for one or more dates. Called by the client-side
    # calendar via fetch; responds JSON.
    def create_unavailability
      person = Current.user.person
      return render(json: { ok: false, error: "No profile" }, status: :unprocessable_entity) unless person

      scope = params[:scope].to_s
      dates = Array(params[:dates]).map { |d| safe_date(d) }.compact
      dates << safe_date(params[:date]) if params[:date].present?
      dates = dates.compact.uniq
      return render(json: { ok: false, error: "No dates" }, status: :unprocessable_entity) if dates.empty?

      if scope == "clear"
        person.staff_unavailabilities.where(date: dates).destroy_all
      elsif SCOPES.include?(scope)
        dates.each do |date|
          record = person.staff_unavailabilities.find_or_initialize_by(date: date)
          record.scope = scope
          record.save!
        end
      else
        return render(json: { ok: false, error: "Invalid scope" }, status: :unprocessable_entity)
      end

      render json: { ok: true }
    end

    private

    # "All Staff" tab: a month calendar of every staffer's shifts in the orgs the
    # current user is house staff at. Same finalized-week gate as the personal
    # view, so drafts stay hidden. Reuses the shared month_calendar component.
    def load_all_staff_calendar(people_ids, finalized_weeks)
      @staff_org_ids = OrganizationStaffMember.active
        .where(person_id: people_ids)
        .distinct
        .pluck(:organization_id)
      @multi_org = @staff_org_ids.size > 1

      @cal_month = (safe_date(params[:month]) || Date.current).beginning_of_month
      # Don't let users page into the past — earliest navigable month is this one.
      @cal_month = Date.current.beginning_of_month if @cal_month < Date.current.beginning_of_month

      # Cover the full grid (a month view can spill into adjacent weeks).
      range_start = @cal_month.beginning_of_week(:sunday)
      range_end   = @cal_month.end_of_month.end_of_week(:sunday)

      shifts =
        if @staff_org_ids.any?
          Shift.where(organization_id: @staff_org_ids)
               .where(starts_at: range_start.beginning_of_day..range_end.end_of_day)
               .includes(:house_role, :additional_roles, :organization, shift_assignments: :person)
               .ordered
               .to_a
        else
          []
        end

      # Hide shifts whose week isn't finalized yet (matches the personal view).
      shifts.select! do |s|
        finalized_weeks.include?([ s.organization_id, s.starts_at.to_date.beginning_of_week ])
      end

      @shifts_by_date = shifts.group_by { |s| s.starts_at.to_date }
    end

    def safe_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

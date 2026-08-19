# frozen_string_literal: true

module My
  # Talent-side view of house staffing shifts the user has been assigned to
  # (the Staffing module's counterpart to "My Shows & Events"), plus the place
  # where staff mark the dates they're unavailable to work.
  class ShiftsController < ApplicationController
    def index
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      @people_by_id = @people.index_by(&:id)
      @my_person_ids = people_ids.to_set

      assignments = ShiftAssignment
        .where(person_id: people_ids)
        .joins(:shift)
        .where("shifts.ends_at >= ?", Time.current)
        .includes(:person, shift: [ :house_role, :additional_roles, :organization, :source, { shows: :production } ])
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
      @upcoming_count = @rows.size

      # Staff positions this person has been invited to but hasn't accepted yet —
      # surfaced as a prompt bar so they can accept their onboarding right here.
      # person: :user because onboarding_status asks whether the person has
      # claimed an account, which reads through to their user.
      @pending_onboarding_invites = OrganizationStaffMember.active
        .where(person_id: people_ids)
        .includes(:organization, person: :user)
        .select { |m| m.onboarding_status == :invited }
        .sort_by { |m| m.organization.name.to_s.downcase }

      # Staff who owe a signature on their org's (now-)required agreement — a
      # sign-to-continue prompt surfaces this right here.
      @pending_staff_agreements = OrganizationStaffMember.pending_agreement_signatures(people_ids)

      load_timekeeping(people_ids, finalized_weeks)

      # Unavailability for the calendar/summary (the client renders both). Cover
      # the current month through ~12 months out so month navigation has data.
      person = Current.user.person
      @availability_mode = person&.availability_mode || "unavailable"
      @availability_day_parts = person ? person.staffing_day_parts : StaffingDayParts::DEFAULT_STAFFING_DAY_PARTS
      @unavailability_entries =
        if person
          person.staff_unavailabilities
                .where(date: Date.current.beginning_of_month..(Date.current + 12.months))
                .order(:date)
                .map { |u| { date: u.date.iso8601, scope: u.scope } }
        else
          []
        end

      today = Date.current.iso8601
      @availability_upcoming_count = @unavailability_entries.count { |e| e[:date] >= today }
    end

    # "I can't make it" on an assigned shift — records the decline (+ optional
    # reason) so the org's managers see it on the scheduling page. We don't offer
    # the shift to anyone else automatically.
    def decline
      assignment = find_my_assignment or return
      assignment.decline!(reason: params[:reason])
      ShiftDeclinedNotificationJob.perform_later(assignment.id)
      redirect_to my_shifts_path,
                  notice: "Thanks — we've let #{assignment.shift.organization.name} know you can't make this shift."
    end

    # Undo a "can't make it".
    def undo_decline
      assignment = find_my_assignment or return
      assignment.undo_decline!
      redirect_to my_shifts_path, notice: "You're back on for that shift."
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

      # "all_day", or the key of one of the work time regions this person can mark.
      allowed = [ StaffUnavailability::ALL_DAY ] + person.staffing_day_parts.map { |p| p["key"] }
      if scope == "clear"
        person.staff_unavailabilities.where(date: dates).destroy_all
      elsif allowed.include?(scope)
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

    # Switch between marking unavailable-times vs available-times. Because the
    # marks invert meaning, switching modes clears any existing marks.
    def set_availability_mode
      person = Current.user.person
      return render(json: { ok: false }, status: :unprocessable_entity) unless person

      mode = params[:mode].to_s
      return render(json: { ok: false, error: "Invalid mode" }, status: :unprocessable_entity) unless Person::AVAILABILITY_MODES.include?(mode)

      if person.availability_mode != mode
        person.staff_unavailabilities.delete_all
        person.update!(availability_mode: mode)
      end
      render json: { ok: true }
    end

    private

    # Load a shift assignment that belongs to one of the current user's people.
    def find_my_assignment
      people_ids = Current.user.people.active.pluck(:id)
      assignment = ShiftAssignment.where(person_id: people_ids).find_by(id: params[:id])
      redirect_to(my_shifts_path, alert: "We couldn't find that shift.") and return nil unless assignment

      assignment
    end

    # Timekeeping panel: recent past shifts still to confirm, the worker's logged
    # (unpaid) entries, and a running unpaid-hours total. Same finalized-week gate
    # as the personal shift list.
    def load_timekeeping(people_ids, finalized_weeks)
      window = 30.days.ago.beginning_of_day..Time.current
      past = ShiftAssignment.where(person_id: people_ids)
        .joins(:shift)
        .where("shifts.ends_at >= ? AND shifts.ends_at <= ?", window.begin, window.end)
        .includes(:person, shift: [ :house_role, :additional_roles, :organization, :source ])
        .order("shifts.starts_at DESC")
        .to_a
      past.select! do |a|
        finalized_weeks.include?([ a.shift.organization_id, a.shift.starts_at.to_date.beginning_of_week ])
      end
      confirmed_ids = StaffTimeEntry.where(shift_assignment_id: past.map(&:id)).pluck(:shift_assignment_id).to_set
      @unconfirmed_shifts = past.reject { |a| confirmed_ids.include?(a.id) }

      # Every unpaid entry (pending review + approved) — these are what the worker
      # is still owed staffing pay for.
      @time_entries = StaffTimeEntry.where(person_id: people_ids).unpaid
        .includes(:house_role, shift_assignment: { shift: :house_role })
        .order(started_at: :desc)
        .to_a
      # A little recently-paid history.
      @paid_entries = StaffTimeEntry.where(person_id: people_ids).paid
        .where(paid_at: 90.days.ago..Time.current)
        .includes(:house_role, shift_assignment: { shift: :house_role })
        .order(paid_at: :desc).limit(10).to_a

      # Owed estimate for STAFFING hours (excludes performance payouts). Each
      # entry prices at the role it was worked as — the member default rate is
      # only the fallback for role-less entries.
      members_by_key = OrganizationStaffMember.where(person_id: people_ids)
                                              .includes(staff_role_qualifications: :house_role)
                                              .index_by { |m| [ m.organization_id, m.person_id ] }

      @unpaid_hours = @time_entries.sum { |e| e.hours.to_f }
      @pending_hours = @time_entries.select { |e| e.status == "pending" }.sum { |e| e.hours.to_f }
      @approved_hours = @time_entries.select { |e| e.status == "approved" }.sum { |e| e.hours.to_f }
      @owed_estimate_cents = @time_entries.sum do |e|
        member = members_by_key[[ e.organization_id, e.person_id ]]
        member ? member.amount_cents_for(e.effective_house_role, hours: e.hours) : 0
      end

      @staff_orgs = Organization.where(
        id: OrganizationStaffMember.active.where(person_id: people_ids).distinct.pluck(:organization_id)
      ).order(:name).to_a

      # Qualified roles per org, for the "worked as" picker on self-logged time.
      @staff_roles_by_org = OrganizationStaffMember.active.where(person_id: people_ids)
        .includes(staff_role_qualifications: :house_role)
        .each_with_object({}) do |m, h|
          m.staff_role_qualifications.each do |q|
            next unless q.house_role
            (h[m.organization_id] ||= []) << q.house_role
          end
        end
        .transform_values { |roles| roles.uniq.sort_by(&:name) }

      person = Current.user.person
      @bank_connected = person.respond_to?(:can_receive_payouts?) && person.can_receive_payouts?
    end

    def safe_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

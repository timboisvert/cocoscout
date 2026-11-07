# frozen_string_literal: true

module My
  # Talent-side view of house staffing shifts the user has been assigned to
  # (the Staffing module's counterpart to "My Shows & Events"). When they can
  # work is set on its own page (My::WorkAvailabilityController).
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
        .includes(:person, shift: [ :house_role, :additional_roles, :organization, :source, :shift_vacancies, { shows: :production } ])
        .order("shifts.starts_at ASC")
        .to_a

      # Drafts are hidden: a shift only shows once its org has finalized that
      # week's schedule. Keyed by (organization_id, Monday-of-week).
      finalized_weeks = StaffingFinalization.finalized.pluck(:organization_id, :week_start).to_set
      assignments.select! do |a|
        finalized_weeks.include?([ a.shift.organization_id, a.shift.starts_at.to_date.beginning_of_week ])
      end

      @rows = assignments.map { |a| { assignment: a, shift: a.shift, person: a.person, vacancy: a.active_vacancy } }
      # Shifts they couldn't make that are settled (someone has it, or it's
      # not being filled): their row is gone, so the vacancy stands in for it.
      settled = ShiftVacancy.where(vacated_by_id: people_ids, status: %w[filled not_filling]).upcoming
        .includes(:filled_by, :vacated_by, shift: [ :house_role, :additional_roles, :organization, :source, { shows: :production } ])
        .order("shifts.starts_at ASC")
        .to_a
      settled.select! do |v|
        finalized_weeks.include?([ v.shift.organization_id, v.shift.starts_at.to_date.beginning_of_week ])
      end
      @rows += settled.map { |v| { vacancy: v, shift: v.shift, person: v.vacated_by, outcome: true } }
      @rows.sort_by! { |r| r[:shift].starts_at }
      @rows_by_day = @rows.group_by { |r| r[:shift].starts_at.to_date }
      # How many people to expect at the shows each shift covers, where the
      # organization shows its staff the count (ShiftExpectedAttendance).
      @expected_by_shift = ShiftExpectedAttendance.for(@rows.map { |r| r[:shift] })
      # The shows each shift covers, for its row, its sheet and the hero:
      # with counts where the organization shows them; otherwise, for a
      # show-tied shift, just the shows.
      @show_lines_by_shift = @rows.map { |r| r[:shift] }.uniq.each_with_object({}) do |shift, h|
        lines = @expected_by_shift[shift.id]
        if lines.nil? && (shift.house_role&.show_specific? || shift.shows.any?)
          lines = shift.covered_shows.map { |cs| ShiftExpectedAttendance::Line.new(show: cs, expected: nil) }
        end
        h[shift.id] = Array(lines)
      end
      # Who else is working alongside each shift, among people who've been told.
      shifts = @rows.map { |r| r[:shift] }.uniq
      @also_on_rows_by_shift = ShiftWords.also_on_rows_for(shifts, people_ids)
      @also_on_by_shift = @also_on_rows_by_shift.transform_values { |rows| rows.map { |a| "#{a.person.name} (#{a.shift.role_label})" }.uniq.join(", ") }
      @has_any = @rows.any?
      @upcoming_count = @rows.count { |r| r[:assignment]&.active? }

      # Shifts they've been asked to cover, still open.
      @pending_shift_invitations = pending_shift_invitations(people_ids)

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

      # Staff who still owe their org a W-9. Anyone who hasn't accepted
      # onboarding yet is left out — the onboarding page asks them for it.
      @pending_w9s = OrganizationStaffMember.pending_w9s(people_ids).select(&:acknowledged?)

      load_timekeeping(people_ids, finalized_weeks)
      # The next shift first (plan §5, idea 3): the nearest shift they're on
      # is the page's hero; the list then reads "Then N more".
      @hero = @rows.find { |r| r[:assignment]&.active? }
      @verify_hours = @unconfirmed_shifts.sum { |a| (a.shift.ends_at - a.shift.starts_at) / 3600.0 }

      # The Work availability card: the shape of their week and what's coming up.
      @availability_person = Current.user.person
      @availability_picture = @availability_person && WorkAvailabilityPicture.new(@availability_person)
    end

    # "I can't make it" on an assigned shift: the decline (+ optional note)
    # opens a ShiftVacancy, which tells the org's chosen managers so they can
    # find cover. A shift that's already over has nothing to cover.
    def decline
      assignment = find_my_assignment or return
      if assignment.shift.ends_at < Time.current
        redirect_to my_shifts_path, alert: "That shift is already over." and return
      end

      assignment.decline!(reason: params[:reason])
      redirect_to my_shifts_path,
                  notice: "Thanks — we've let #{assignment.shift.organization.name} know you can't make this shift."
    end

    # "I'm back on": takes the vacancy back while nobody has covered it yet,
    # and the managers hear.
    def undo_decline
      assignment = find_my_assignment or return
      vacancy = assignment.active_vacancy
      if vacancy
        vacancy.reclaim!
      elsif assignment.declined?
        assignment.undo_decline!
      else
        redirect_to my_shifts_path, alert: "That shift has already been covered." and return
      end
      redirect_to my_shifts_path, notice: "You're back on for that shift."
    end

    private

    def pending_shift_invitations(people_ids)
      ShiftVacancyInvitation.unresolved.joins(shift_vacancy: :shift)
                            .where(person_id: people_ids)
                            .includes(shift_vacancy: { shift: [ :house_role, :organization ] })
                            .order("shifts.starts_at ASC")
                            .to_a
    end

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
      # A shift you told them you couldn't make is not a shift you worked, so it
      # never asks you to confirm hours for it — which is how a decline used to
      # turn into payable time.
      past.select! do |a|
        a.active? &&
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
      # The Getting paid card: the next money coming, and each recent day's
      # pay by where it stands (waiting, approved, on its way, deposited).
      @shift_pay = MyShiftPay.new(people_ids)

      @pending_hours = @time_entries.select { |e| e.status == "pending" }.sum { |e| e.hours.to_f }
      @approved_hours = @time_entries.select { |e| e.status == "approved" }.sum { |e| e.hours.to_f }

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
  end
end

# frozen_string_literal: true

module My
  # Worker-side timekeeping: confirm/adjust the hours you were scheduled for, and
  # log ad-hoc time you worked on your own. Managers later pull these unpaid
  # entries into a pay run.
  class TimeEntriesController < ApplicationController
    before_action :set_entry, only: %i[update destroy]

    # Confirm a scheduled shift (shift_assignment_id present) or log ad-hoc time.
    def create
      entry =
        if params[:shift_assignment_id].present?
          build_from_shift
        else
          build_manual
        end
      return if performed?

      entry.assign_attributes(time_params)
      assign_manual_role(entry)
      return if reject_roleless_manual_entry(entry)

      if entry.save
        redirect_to my_shifts_path, notice: "Hours saved."
      else
        redirect_to my_shifts_path, alert: entry.errors.full_messages.to_sentence
      end
    end

    def update
      @entry.assign_attributes(time_params)
      assign_manual_role(@entry)
      return if reject_roleless_manual_entry(@entry)

      if @entry.save
        redirect_to my_shifts_path, notice: "Hours updated."
      else
        redirect_to my_shifts_path, alert: @entry.errors.full_messages.to_sentence
      end
    end

    def destroy
      @entry.destroy
      redirect_to my_shifts_path, notice: "Time entry removed."
    end

    private

    def my_person_ids
      @my_person_ids ||= Current.user.people.pluck(:id)
    end

    def build_from_shift
      assignment = ShiftAssignment.where(person_id: my_person_ids).find_by(id: params[:shift_assignment_id])
      unless assignment
        redirect_to my_shifts_path, alert: "That shift isn't yours to confirm."
        return
      end

      shift = assignment.shift
      # Reuse an existing confirmation for this assignment (idempotent confirm).
      StaffTimeEntry.find_or_initialize_by(shift_assignment_id: assignment.id).tap do |e|
        e.organization = shift.organization
        e.person = assignment.person
        e.source = "shift"
        e.house_role_id ||= shift.house_role_id # the work's role prices the hours
        e.started_at ||= shift.starts_at
        e.ended_at ||= shift.ends_at
      end
    end

    def build_manual
      person = Current.user.person
      unless person
        redirect_to my_shifts_path, alert: "Complete your profile first."
        return
      end

      organization = staff_organizations.find_by(id: params[:organization_id]) || staff_organizations.first
      unless organization
        redirect_to my_shifts_path, alert: "You're not on any staff roster yet."
        return
      end

      StaffTimeEntry.new(organization: organization, person: person, source: "manual")
    end

    # Orgs the current user is active house staff at (valid targets for ad-hoc time).
    def staff_organizations
      Organization.where(id: OrganizationStaffMember.active.where(person_id: my_person_ids).distinct.pluck(:organization_id))
    end

    def set_entry
      # Only your own, still-unpaid entries can be edited or removed.
      @entry = StaffTimeEntry.unpaid.where(person_id: my_person_ids).find(params[:id])
    end

    def time_params
      params.permit(:started_at, :ended_at, :notes)
    end

    # Self-logged work carries the role it was done as (that's what prices the
    # hours). Shift confirmations keep the shift's role — the param is ignored.
    def assign_manual_role(entry)
      return unless entry.source == "manual" && params.key?(:house_role_id)

      entry.house_role_id = params[:house_role_id].presence
    end

    # Self-logged hours must name the role they were worked as whenever the
    # person has qualified roles to pick from — the role is what prices the
    # work. (A person with no qualified roles at the org falls back to their
    # default rate; that's the only role-less case left.)
    # Redirects (and returns true) when the entry is rejected.
    def reject_roleless_manual_entry(entry)
      return false unless entry.source == "manual" && entry.house_role_id.blank?

      member = OrganizationStaffMember.active
                                      .includes(staff_role_qualifications: :house_role)
                                      .find_by(organization_id: entry.organization_id, person_id: my_person_ids)
      return false unless member&.staff_role_qualifications&.any? { |q| q.house_role.present? }

      redirect_to my_shifts_path, alert: "Pick the role you worked as — it's what sets the pay for your hours."
      true
    end
  end
end

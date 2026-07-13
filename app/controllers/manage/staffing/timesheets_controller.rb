# frozen_string_literal: true

module Manage
  module Staffing
    # The manager's hours-approval queue. Workers submit time on My Shifts
    # (confirming scheduled shifts or logging ad-hoc work); those entries land
    # here as "pending review". A manager signs off on them, at which point they
    # become pullable into a pay run (see PayController). This is the review step
    # that sits between "worker submitted" and "manager pays".
    class TimesheetsController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def index
        entries = Current.organization.staff_time_entries.pending
                         .includes(:person, shift_assignment: { shift: :house_role })
                         .chronological

        # Group by person so the manager reviews one teammate at a time.
        @groups = entries.group_by(&:person)
                         .sort_by { |person, _| person.name.to_s.downcase }
        @total_entries = entries.size
        @total_hours = entries.sum(&:hours)
      end

      # Sign off on submitted hours. Scoped to pending entries only, so this can
      # never re-approve or disturb anything already approved or paid. Approves a
      # single person's queue (person_id) or the whole org queue (all=true).
      def approve
        scope = Current.organization.staff_time_entries.pending
        scope = scope.for_person(params[:person_id]) if params[:person_id].present?

        unless params[:person_id].present? || params[:all].present?
          redirect_to manage_staffing_timesheets_path, alert: "Nothing selected to approve." and return
        end

        count = scope.update_all(
          approved_at: Time.current,
          approved_by_id: Current.user.id,
          updated_at: Time.current
        )

        redirect_to manage_staffing_timesheets_path,
                    notice: count.positive? ? "Approved #{helpers.pluralize(count, 'hour entry')}." : "Those hours were already handled."
      end

      # History of hours a manager has signed off on, newest first and grouped by
      # month. Approved-but-unpaid entries can still be corrected (unapprove →
      # edit → reapprove); once an entry is paid it's locked here for the record.
      def approved
        entries = Current.organization.staff_time_entries.signed_off
                         .includes(:person, :approved_by, shift_assignment: { shift: :house_role })
                         .order(started_at: :desc)

        @months = entries.group_by { |e| e.started_at.beginning_of_month }
                         .sort_by { |month, _| month }.reverse
        @total_hours = entries.sum(&:hours)
        @total_entries = entries.size
      end

      # Send an approved entry back to the pending queue so it can be corrected
      # and re-approved. Paid entries are locked and can't be unapproved.
      def unapprove
        entry = find_editable_entry
        return unless entry

        entry.update!(approved_at: nil, approved_by: nil)
        redirect_to manage_approved_staffing_timesheets_path, notice: "Sent that entry back for review."
      end

      def edit
        @entry = find_editable_entry
      end

      # Correct the worked time on an entry (unpaid only). For the audit trail,
      # any edit sends the entry back to "pending review": the manager is then
      # offered a re-approve step in the same modal (see the :saved state in the
      # edit view). Renders the modal frame rather than redirecting so the flow
      # stays in one place.
      def update
        @entry = find_editable_entry
        return unless @entry

        if @entry.update(entry_params.merge(approved_at: nil, approved_by: nil))
          @saved = true
          render :edit
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # Sign off again on an entry that was just edited (and thereby kicked back to
      # pending). Full-page redirect so the approved-hours list reflects it.
      def reapprove
        entry = find_editable_entry
        return unless entry

        entry.update!(approved_at: Time.current, approved_by: Current.user)
        redirect_to manage_approved_staffing_timesheets_path, notice: "Re-approved those hours."
      end

      private

      # Entries are editable only while unpaid; once pulled into a pay run they're
      # settled and must stay put. Redirects (and returns nil) otherwise.
      def find_editable_entry
        entry = Current.organization.staff_time_entries.find(params[:id])
        if entry.paid?
          redirect_to manage_approved_staffing_timesheets_path, alert: "That entry has been paid and can't be changed."
          return nil
        end
        entry
      end

      def entry_params
        params.require(:staff_time_entry).permit(:started_at, :ended_at, :notes)
      end
    end
  end
end

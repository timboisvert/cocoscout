# frozen_string_literal: true

module Manage
  module Staffing
    # The manager's hours-approval queue. Workers submit time on My Shifts
    # (confirming scheduled shifts or logging ad-hoc work); those entries land
    # here as "pending review". A manager signs off on them, at which point they
    # become pullable into a pay run (see PayController). This is the review step
    # that sits between "worker submitted" and "manager pays".
    class TimesheetsController < Manage::ManageController
      # Rows rendered in the approval queue at once. The totals above it are
      # always computed over everything pending, capped or not.
      PENDING_LIMIT = 100

      before_action :ensure_org_owner_or_manager

      def index
        pending = Current.organization.staff_time_entries.pending

        # Totals come from SQL over the whole queue, so capping the rows below
        # can't quietly shrink the numbers a manager is reading.
        @total_entries = pending.count
        @total_hours = pending.sum(:hours)
        # "Approve everything" really does approve everything, so the count in
        # its confirmation has to cover the whole queue, not just what's shown.
        @total_people = pending.distinct.count(:person_id)

        # additional_roles because each row renders shift.role_label, and the
        # person's headshot preload because the queue is grouped by person.
        entries = pending.includes(:house_role,
                                   person: Manage::StaffingController::HEADSHOT_PRELOAD,
                                   shift_assignment: { shift: [ :house_role, :additional_roles ] })
                         .chronological
                         .limit(PENDING_LIMIT)
                         .to_a
        @shown_entries = entries.size

        # Group by person so the manager reviews one teammate at a time.
        @groups = entries.group_by(&:person)
                         .sort_by { |person, _| person.name.to_s.downcase }
        # Members (with role rates) so each entry can show what approving it
        # will cost — priced at the role the work was done as.
        @members_by_person_id = Current.organization.organization_staff_members
                                       .includes(staff_role_qualifications: :house_role)
                                       .index_by(&:person_id)
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
        @current_month = parse_month(params[:month])

        entries = Current.organization.staff_time_entries.signed_off
                         .includes(:person, :approved_by, shift_assignment: { shift: :house_role })
                         .where(started_at: @current_month.beginning_of_month.beginning_of_day..
                                            @current_month.end_of_month.end_of_day)
                         .order(:started_at)

        @items_by_date = entries.group_by { |e| e.started_at.to_date }
        @month_hours = entries.sum(&:hours)
        @month_entries = entries.size
      end

      # Send an approved entry back to the pending queue so it can be corrected
      # and re-approved. Paid entries are locked and can't be unapproved.
      def unapprove
        entry = find_editable_entry
        return unless entry

        was_approved = entry.approved_at.present?
        entry.update!(approved_at: nil, approved_by: nil)
        if was_approved
          redirect_to manage_approved_staffing_timesheets_path(month: entry.started_at.strftime("%Y-%m")),
                      notice: "Sent that entry back for review."
        else
          # Already in the queue (adjusted from the pending list) — just go back to it.
          redirect_to manage_staffing_timesheets_path, notice: "Kept in your review queue."
        end
      end

      def edit
        @entry = find_editable_entry
        return unless @entry

        load_adjust_context
      end

      # Correct the worked time on an entry (unpaid only). For the audit trail,
      # any edit sends the entry back to "pending review": the manager is then
      # offered a re-approve step in the same modal (see the :saved state in the
      # edit view). Renders the modal frame rather than redirecting so the flow
      # stays in one place.
      def update
        @entry = find_editable_entry
        return unless @entry

        # Was it already approved before this edit? Drives the "re-approve" vs
        # "approve" wording on the saved confirmation.
        @was_approved = @entry.approved_at.present?

        if @entry.update(entry_params.merge(approved_at: nil, approved_by: nil))
          @saved = true
          render :edit
        else
          load_adjust_context
          render :edit, status: :unprocessable_entity
        end
      end

      # Sign off again on an entry that was just edited (and thereby kicked back to
      # pending). The adjust modal opens from both the review queue and the
      # approved-hours page, so land back wherever the manager was working.
      def reapprove
        entry = find_editable_entry
        return unless entry

        entry.update!(approved_at: Time.current, approved_by: Current.user)
        redirect_back fallback_location: manage_approved_staffing_timesheets_path, notice: "Re-approved those hours."
      end

      # These hours were already settled outside CocoScout (e.g. a payroll check
      # cut before staff pay moved onto the platform). Marks the entry paid —
      # approving it in the same stroke if it was still pending — so it can never
      # be pulled into a pay run and the worker sees it as handled.
      def mark_paid_offline
        entry = find_editable_entry
        return unless entry

        was_pending = entry.approved_at.blank?
        entry.mark_paid_offline!(Current.user, note: params[:note], paid_on: params[:paid_on])

        destination = was_pending ? manage_staffing_timesheets_path
                                  : manage_approved_staffing_timesheets_path(month: entry.started_at.strftime("%Y-%m"))
        redirect_to destination,
                    notice: "Marked #{entry.person.name}'s #{helpers.number_with_precision(entry.hours, precision: 2, strip_insignificant_zeros: true)}h on #{entry.started_at.strftime('%b %-d')} as already paid outside CocoScout."
      end

      # Undo a mistaken already-paid mark. The sign-off sticks, so the entry
      # returns to "approved" and is pullable into a pay run again.
      def unmark_paid_offline
        entry = Current.organization.staff_time_entries.find(params[:id])
        unless entry.paid_offline?
          redirect_to manage_approved_staffing_timesheets_path, alert: "That entry isn't marked as paid outside CocoScout." and return
        end

        entry.unmark_paid_offline!
        redirect_to manage_approved_staffing_timesheets_path(month: entry.started_at.strftime("%Y-%m")),
                    notice: "Unmarked — those hours are back to approved and can be paid on a run."
      end

      # Reject a submitted entry: remove it from the queue. Unpaid only (a paid
      # entry is settled and can't be rejected). The worker can re-submit if it
      # was a mistake.
      def reject
        entry = find_editable_entry
        return unless entry

        entry.destroy!
        redirect_to manage_staffing_timesheets_path, notice: "Rejected that time entry."
      end

      private

      # Turn a "YYYY-MM" param into the first of that month, defaulting to the
      # current month. Bad input falls back to this month rather than erroring.
      def parse_month(value)
        return Date.current.beginning_of_month if value.blank?

        Date.strptime(value, "%Y-%m").beginning_of_month
      rescue ArgumentError
        Date.current.beginning_of_month
      end

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
        params.require(:staff_time_entry).permit(:started_at, :ended_at, :notes, :house_role_id)
      end

      # The Adjust modal lets a manager reprice an entry by changing the role the
      # work was done as, so it needs the org's roles and this person's member
      # record (which knows their rate for each role).
      def load_adjust_context
        @member = Current.organization.organization_staff_members
                         .includes(staff_role_qualifications: :house_role)
                         .find_by(person_id: @entry.person_id)
        @adjust_roles = Current.organization.house_roles.order(:name).to_a
      end
    end
  end
end

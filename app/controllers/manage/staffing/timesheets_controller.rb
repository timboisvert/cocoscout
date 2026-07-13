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
    end
  end
end

# frozen_string_literal: true

module Manage
  module Staffing
    # A shift someone can't make: the page where a manager finds cover. For
    # now it opens that day in Scheduling, where the can't-make-it sheet and
    # Find someone are; the page itself comes next.
    class VacanciesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def show
        vacancy = ShiftVacancy.joins(:shift).where(shifts: { organization_id: Current.organization.id }).find(params[:id])
        redirect_to manage_staffing_scheduling_path(day: vacancy.shift.starts_at.to_date.iso8601)
      end
    end
  end
end

# frozen_string_literal: true

module Manage
  module Staffing
    # Manage the org's department list. Rendered inside a Turbo-frame modal from
    # the staff wizard / edit page; create + destroy redirect back to #index so
    # the frame re-renders in place.
    class DepartmentsController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def index
        @departments = Current.organization.departments.ordered
      end

      def create
        name = params.dig(:department, :name).to_s.strip
        if name.present?
          position = (Current.organization.departments.maximum(:position) || 0) + 1
          Current.organization.departments.create(name: name, position: position)
        end
        redirect_to manage_staffing_departments_path
      end

      def destroy
        Current.organization.departments.find_by(id: params[:id])&.destroy
        redirect_to manage_staffing_departments_path
      end
    end
  end
end

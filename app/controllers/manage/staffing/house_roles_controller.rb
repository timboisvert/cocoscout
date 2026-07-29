# frozen_string_literal: true

module Manage
  module Staffing
    class HouseRolesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_house_role, only: %i[edit update destroy]

      def index
        @house_roles = Current.organization.house_roles.ordered
      end

      # Turbo-frame role manager, embedded in a modal on the staff wizard / edit
      # page. Add/remove here re-renders the frame in place.
      def editor
        @house_roles = Current.organization.house_roles.active.ordered
      end

      # new/edit aren't used in the normal flow — the modal on the index page
      # handles both. Redirect direct navigation to the index so we don't have
      # to maintain duplicate full-page form views.
      def new
        redirect_to manage_staffing_house_roles_path
      end

      def edit
        redirect_to manage_staffing_house_roles_path
      end

      def create
        @house_role = Current.organization.house_roles.new(house_role_params)
        @house_role.position = (Current.organization.house_roles.maximum(:position) || 0) + 1
        if @house_role.save
          redirect_to roles_redirect_target, notice: "House role added."
        else
          redirect_to roles_redirect_target,
                      alert: "Couldn't add role: #{@house_role.errors.full_messages.to_sentence}"
        end
      end

      def update
        if @house_role.update(house_role_params)
          redirect_to manage_staffing_house_roles_path, notice: "House role updated."
        else
          redirect_to manage_staffing_house_roles_path,
                      alert: "Couldn't update role: #{@house_role.errors.full_messages.to_sentence}"
        end
      end

      def destroy
        if @house_role.shifts.any?
          @house_role.archive!
          redirect_to roles_redirect_target, notice: "House role archived (existing shifts kept)."
        else
          @house_role.destroy!
          redirect_to roles_redirect_target, notice: "House role removed."
        end
      end

      private

      # When add/remove is triggered from the embedded editor frame, redirect back
      # to it so Turbo re-renders the frame in place; otherwise the full page.
      def roles_redirect_target
        params[:return_to] == "editor" ? manage_staffing_house_roles_editor_path : manage_staffing_house_roles_path
      end

      def set_house_role
        @house_role = Current.organization.house_roles.find(params[:id])
      end

      def house_role_params
        params.require(:house_role).permit(
          :name, :role_type, :location_id, :default_required_count,
          :default_hourly_rate_dollars
        )
      end
    end
  end
end

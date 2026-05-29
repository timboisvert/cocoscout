# frozen_string_literal: true

module Manage
  module Staffing
    class HouseRolesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_house_role, only: %i[edit update destroy]

      def index
        @house_roles = Current.organization.house_roles.ordered
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
          redirect_to manage_staffing_house_roles_path, notice: "House role added."
        else
          redirect_to manage_staffing_house_roles_path,
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
          redirect_to manage_staffing_house_roles_path, notice: "House role archived (existing shifts kept)."
        else
          @house_role.destroy!
          redirect_to manage_staffing_house_roles_path, notice: "House role removed."
        end
      end

      private

      def set_house_role
        @house_role = Current.organization.house_roles.find(params[:id])
      end

      def house_role_params
        params.require(:house_role).permit(
          :name, :location_id, :default_required_count,
          :default_start_offset_minutes, :default_end_offset_minutes
        )
      end
    end
  end
end

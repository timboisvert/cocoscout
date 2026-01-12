# frozen_string_literal: true

module Manage
  class EmailGroupsController < ManageController
    before_action :set_production
    before_action :set_audition_cycle
    before_action :set_email_group, only: %i[update destroy]

    def create
      @email_group = @audition_cycle.email_groups.new(email_group_params)

      if @email_group.save
        render json: { id: @email_group.id }
      else
        render json: { errors: @email_group.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @email_group.update(email_group_params)
        head :ok
      else
        render json: { errors: @email_group.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @email_group.destroy
      head :ok
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_audition_cycle
      @audition_cycle = @production.audition_cycle
    end

    def set_email_group
      @email_group = @audition_cycle.email_groups.find(params[:id])
    end

    def email_group_params
      params.require(:email_group).permit(:group_id, :name, :email_template, :group_type)
    end
  end
end

# frozen_string_literal: true

module Manage
  class CastAssignmentStagesController < ManageController
    before_action :set_production
    before_action :set_audition_cycle
    before_action :set_stage, only: %i[update destroy]

    def create
      @stage = @audition_cycle.cast_assignment_stages.new(create_stage_params)
      if @stage.save
        head :ok
      else
        render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @stage.update(stage_params)
        head :ok
      else
        render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      if @stage.destroy
        head :ok
      else
        render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
      end
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
      @audition_cycle = @production.active_audition_cycle
      return if @audition_cycle

      redirect_to manage_production_path(@production), alert: "No active audition cycle. Please create one first."
    end

    def set_stage
      @stage = @audition_cycle.cast_assignment_stages.find(params[:id])
    end

    def stage_params
      params.require(:cast_assignment_stage).permit(:email_group_id)
    end

    def create_stage_params
      params.require(:cast_assignment_stage).permit(:person_id, :talent_pool_id, :email_group_id, :status)
    end
  end
end

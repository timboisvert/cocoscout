module Manage
  class CastAssignmentStagesController < ManageController
    before_action :set_production
    before_action :set_call_to_audition
    before_action :set_stage, only: [ :update, :destroy ]

    def create
      @stage = @call_to_audition.cast_assignment_stages.new(create_stage_params)
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
      @production = Current.production_company.productions.find(params[:production_id])
    end

    def set_call_to_audition
      @call_to_audition = @production.active_call_to_audition
      unless @call_to_audition
        redirect_to manage_production_path(@production), alert: "No active call to audition. Please create one first."
      end
    end

    def set_stage
      @stage = @call_to_audition.cast_assignment_stages.find(params[:id])
    end

    def stage_params
      params.require(:cast_assignment_stage).permit(:email_group_id)
    end

    def create_stage_params
      params.require(:cast_assignment_stage).permit(:person_id, :cast_id, :email_group_id, :status)
    end
  end
end

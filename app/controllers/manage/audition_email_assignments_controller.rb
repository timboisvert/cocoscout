# AuditionEmailAssignments track which email template each auditionee receives.
# This is SEPARATE from cast assignments (CastAssignmentStage).
# - People in casts can receive custom emails
# - People NOT in casts can also receive custom emails
# - No email assignment = they receive the default email for their status
module Manage
  class AuditionEmailAssignmentsController < ManageController
    before_action :set_production
    before_action :set_call_to_audition
    before_action :set_assignment, only: [ :update, :destroy ]

    def create
      @assignment = @call_to_audition.audition_email_assignments.new(assignment_params)
      if @assignment.save
        head :ok
      else
        render json: { errors: @assignment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @assignment.update(assignment_params)
        head :ok
      else
        render json: { errors: @assignment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      if @assignment.destroy
        head :ok
      else
        render json: { errors: @assignment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_production
      @production = Current.production_company.productions.find(params[:production_id])
    end

    def set_call_to_audition
      @call_to_audition = @production.call_to_audition
    end

    def set_assignment
      @assignment = @call_to_audition.audition_email_assignments.find(params[:id])
    end

    def assignment_params
      params.require(:audition_email_assignment).permit(:person_id, :email_group_id)
    end
  end
end

# frozen_string_literal: true

# AuditionEmailAssignments track which email template each auditionee receives.
# This is SEPARATE from cast assignments (CastAssignmentStage).
# - People in casts can receive custom emails
# - People NOT in casts can also receive custom emails
# - No email assignment = they receive the default email for their status
module Manage
  class AuditionEmailAssignmentsController < ManageController
    before_action :set_production
    before_action :set_audition_cycle
    before_action :set_assignment, only: %i[update destroy]

    def create
      @assignment = @audition_cycle.audition_email_assignments.new(assignment_params)
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
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_audition_cycle
      @audition_cycle = @production.audition_cycle
    end

    def set_assignment
      @assignment = @audition_cycle.audition_email_assignments.find(params[:id])
    end

    def assignment_params
      params.require(:audition_email_assignment).permit(:person_id, :email_group_id)
    end
  end
end

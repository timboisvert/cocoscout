module Manage
  class EmailGroupsController < ManageController
    before_action :set_production
    before_action :set_call_to_audition
    before_action :set_email_group, only: [ :destroy ]

    def create
      @email_group = @call_to_audition.email_groups.new(email_group_params)

      if @email_group.save
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
      @production = Current.production_company.productions.find(params[:production_id])
    end

    def set_call_to_audition
      @call_to_audition = @production.call_to_audition
    end

    def set_email_group
      @email_group = @call_to_audition.email_groups.find(params[:id])
    end

    def email_group_params
      params.require(:email_group).permit(:group_id, :name, :email_template, :group_type)
    end
  end
end

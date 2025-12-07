# frozen_string_literal: true

module Manage
  class RolesController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_role, only: %i[edit update destroy]
    before_action :ensure_user_is_manager, except: %i[index]

    def index
      @roles = @production.roles.order(:position, :created_at)
      @role = @production.roles.new
    end

    def edit; end

    def create
      @roles = @production.roles.order(:position, :created_at)
      @role = @production.roles.new(role_params)

      # Set position to be at the end of the list
      max_position = @production.roles.maximum(:position) || -1
      @role.position = max_position + 1

      if @role.save
        redirect_to manage_production_roles_path(@production), notice: "Role was successfully created"
      else
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @role.update(role_params)
        redirect_to manage_production_roles_path(@production), notice: "Role was successfully updated",
                                                               status: :see_other
      else
        @roles = @production.roles.order(:position, :created_at)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @role.destroy!
      redirect_to manage_production_roles_path(@production), notice: "Role was successfully deleted", status: :see_other
    end

    def reorder
      role_ids = params[:role_ids]
      role_ids.each_with_index do |id, index|
        @production.roles.find(id).update(position: index)
      end
      head :ok
    end

    private

    def set_production
      @production = Current.organization.productions.find(params.expect(:production_id))
    end

    def set_role
      @role = @production.roles.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def role_params
      params.expect(role: [ :name ])
    end
  end
end

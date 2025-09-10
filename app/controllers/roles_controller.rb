class RolesController < ApplicationController
  before_action :set_production
  before_action :set_role, only: %i[ show edit update destroy ]

  def index
    @roles = @production.roles.all
    @role = @production.roles.new
  end

  def show
  end

  def new
    @role = @production.roles.new
  end

  def edit
  end

  def create
    @roles = @production.roles.all
    @role = @production.roles.new(role_params)

    if @role.save
      redirect_to production_roles_path(@production), notice: "Role was successfully created."
    else
      render :index, status: :unprocessable_entity
    end
  end

  def update
    @roles = @production.roles.all
    if @role.update(role_params)
      redirect_to production_roles_path(@production), notice: "Role was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @role.destroy!
    redirect_to production_roles_path(@production), notice: "Role was successfully deleted.", status: :see_other
  end

  private
    def set_production
      @production = Production.find(params.expect(:production_id))
    end

    def set_role
      @role = @production.roles.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def role_params
      params.expect(role: [ :name ])
    end
end

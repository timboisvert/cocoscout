class Manage::ShowPersonRoleAssignmentsController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_show
  before_action :set_show_person_role_assignment, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_manager

  def index
    @show_person_role_assignments = @show.show_person_role_assignments.all
  end

  def show
  end

  def new
    @show_person_role_assignment = @show.show_person_role_assignments.new
  end

  def edit
  end

  def create
    @show_person_role_assignment = @show.show_person_role_assignments.new(show_person_role_assignment_params)

    if @show_person_role_assignment.save
      redirect_to @show_person_role_assignment, notice: "Show person role assignment was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @show_person_role_assignment.update(show_person_role_assignment_params)
      redirect_to @show_person_role_assignment, notice: "Show person role assignment was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @show_person_role_assignment.destroy!
    redirect_to show_person_role_assignments_path, notice: "Show person role assignment was successfully deleted", status: :see_other
  end

  private
    def set_production
      @production = Current.organization.productions.find(params.expect(:production_id))
    end

    def set_show
      @show = @production.shows.find(params.expect(:show_id))
    end

    def set_show_person_role_assignment
      @show_person_role_assignment = @show.show_person_role_assignments.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def show_person_role_assignment_params
      params.expect(show_person_role_assignment: [ :show_id, :person_id, :role_id ])
    end
end

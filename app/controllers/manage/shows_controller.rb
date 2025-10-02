class Manage::ShowsController < Manage::ManageController
  before_action :set_show, only: %i[ show edit update destroy assign_person_to_role remove_person_from_role ]
  before_action :set_production, except: %i[ assign_person_to_role remove_person_from_role ]

  def index
    @shows = @production.shows.all
  end

  def show
  end

  def new
    @show = @production.shows.new

    if params[:duplicate].present?
      original = @production.shows.find_by(id: params[:duplicate])
      if original.present?
        @show.date_and_time = original.date_and_time
        @show.secondary_name = original.secondary_name
      end
    end
  end

  def edit
  end

  def create
    @show = Show.new(show_params)
    @show.production = @production

    if @show.save
      redirect_to manage_production_shows_path(@production), notice: "Show was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @show.update(show_params)
      redirect_to manage_production_shows_path(@production), notice: "Show was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @show.destroy!
    redirect_to manage_production_shows_path(@production), notice: "Show was successfully deleted.", status: :see_other
  end

  def assign_person_to_role
    # Get the person and the role
    person = Person.find(params[:person_id])
    role = Role.find(params[:role_id])

    # If this role already has someone in it for this show, remove the assignment
    existing_assignments = @show.show_person_role_assignments.where(role: role)
    existing_assignments.destroy_all if existing_assignments.any?

    # Make the assignment
    assignment = @show.show_person_role_assignments.find_or_initialize_by(person: person, role: role)
    assignment.save!

    # Generate the HTML to return
    cast_members_html = render_to_string(partial: "manage/shows/cast_members_list", locals: { show: @show })
    roles_html = render_to_string(partial: "manage/shows/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html }
  end

  def remove_person_from_role
    assignment = @show.show_person_role_assignments.find(params[:assignment_id])
    assignment.destroy! if assignment

    # Generate the HTML to return
    cast_members_html = render_to_string(partial: "manage/shows/cast_members_list", locals: { show: @show })
    roles_html = render_to_string(partial: "manage/shows/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html }
  end



  private
    def set_show
      @show = Show.find(params.expect(:id))
    end

    def set_production
      @production = Production.find(params.expect(:production_id))
    end

    # Only allow a list of trusted parameters through.
    def show_params
      params.require(:show).permit(:secondary_name, :date_and_time, :poster, :production_id, :location_id)
    end
end

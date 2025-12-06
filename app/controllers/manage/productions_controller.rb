class Manage::ProductionsController < Manage::ManageController
  before_action :set_production, only: %i[ show edit update destroy confirm_delete ]
  before_action :check_production_access, only: %i[ show edit update destroy confirm_delete ]
  before_action :ensure_user_is_global_manager, only: %i[ new create ]
  before_action :ensure_user_is_manager, only: %i[ edit update destroy confirm_delete ]
  skip_before_action :show_manage_sidebar, only: %i[ index new create ]

  def index
    # Redirect to production selection
    redirect_to select_production_path
  end

  def show
    set_production_in_session
    @dashboard = DashboardService.new(@production).generate
  end

  def new
    @production = Current.organization.productions.new
  end

  def edit
    # Eager load posters for visual assets tab
    @production = Current.organization.productions.includes(:posters).find_by(id: params[:id])
  end

  def create
    @production = Current.organization.productions.new(production_params)

    if @production.save
      set_production_in_session
      # Auto-dismiss welcome screen after creating first production
      if Current.user.welcomed_production_at.nil?
        Current.user.update(welcomed_production_at: Time.current)
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @production.update(production_params)
      set_production_in_session
      redirect_to [ :manage, @production ], notice: "Production was successfully updated", status: :see_other and return
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def confirm_delete
    # Gather stats about what will be deleted
    @shows_count = @production.shows.count
    @roles_count = @production.roles.count
    @posters_count = @production.posters.count
    @audition_cycles_count = @production.audition_cycles.count
    @questionnaires_count = @production.questionnaires.count
  end

  def destroy
    if Current.organization && Current.user
      session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] = nil
      @production.destroy!
      redirect_to manage_productions_path, notice: "Production was successfully deleted", status: :see_other and return
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_production
      @production = Current.organization.productions.find_by(id: params[:id])
      unless @production
        redirect_to manage_productions_path, alert: "Not authorized or not found" and return
      end
    end

    def set_production_in_session
      if Current.organization && Current.user

        # Make sure we have the sessions hash set for production IDs
        session[:current_production_id_for_organization] ||= {}

        # Store the current one
        previous_production_id = session[:current_production_id_for_organization]&.dig("#{Current.user&.id}_#{Current.organization&.id}")

        # Set the new one
        session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] = @production.id

        # If the production changed, redirect to the manage home so the left nav resets
        if previous_production_id != @production.id
          redirect_to manage_path and return
        end
      end
    end

    # Only allow a list of trusted parameters through.
    def production_params
      params.require(:production).permit(:name, :logo, :description, :contact_email).merge(organization_id: Current.organization&.id)
    end
end

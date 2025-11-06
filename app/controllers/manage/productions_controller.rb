class Manage::ProductionsController < Manage::ManageController
  before_action :set_production, only: %i[ show edit update destroy ]
  before_action :check_production_access, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_global_manager, only: %i[ new create ]
  before_action :ensure_user_is_manager, only: %i[ edit update destroy ]
  skip_before_action :show_manage_sidebar, only: %i[ index new create ]

  def index
    @productions = Current.user.accessible_productions
    @production = Production.new
  end

  def show
    set_production_in_session
    @dashboard = DashboardService.new(@production).generate
  end

  def new
    @production = Current.production_company.productions.new
  end

  def edit
  end

  def create
    @production = Current.production_company.productions.new(production_params)

    if @production.save
      set_production_in_session
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

  def destroy
    if Current.production_company && Current.user
      session[:current_production_id_for_company]["#{Current.user&.id}_#{Current.production_company&.id}"] = nil
      @production.destroy!
      redirect_to manage_productions_path, notice: "Production was successfully deleted", status: :see_other and return
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_production
      @production = Current.production_company.productions.find_by(id: params[:id])
      unless @production
        redirect_to manage_productions_path, alert: "Not authorized or not found" and return
      end
    end

    def set_production_in_session
      if Current.production_company && Current.user

        # Make sure we have the sessions hash set for production IDs
        session[:current_production_id_for_company] ||= {}

        # Store the current one
        previous_production_id = session[:current_production_id_for_company]&.dig("#{Current.user&.id}_#{Current.production_company&.id}")

        # Set the new one
        session[:current_production_id_for_company]["#{Current.user&.id}_#{Current.production_company&.id}"] = @production.id

        # If the production changed, redirect to the manage home so the left nav resets
        if previous_production_id != @production.id
          redirect_to manage_path and return
        end
      end
    end

    # Only allow a list of trusted parameters through.
    def production_params
      params.require(:production).permit(:name, :logo, :description, :contact_email).merge(production_company_id: Current.production_company&.id)
    end
end

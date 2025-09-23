class Manage::ProductionCompaniesController < Manage::ManageController
  before_action :set_production_company, only: %i[ edit update destroy ]
  skip_before_action :show_manage_sidebar

  def new
    @production_company = ProductionCompany.new
  end

  def edit
  end

  def create
    @production_company = ProductionCompany.new(production_company_params)

    if @production_company.save
      # Assign creator as admin
      UserRole.create!(user: Current.user, production_company: @production_company, role: "admin")
      session[:current_production_company_id] ||= {}
      session[:current_production_company_id]["#{Current.user&.id}"] = @production_company.id
      redirect_to manage_path, notice: "Production company was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @production_company.update(production_company_params)
      redirect_to @production_company, notice: "Production company was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @production_company.destroy!
    redirect_to production_companies_path, notice: "Production company was successfully destroyed.", status: :see_other
  end

  def select
    @production_companies = Current.user.production_companies
    @production_company = ProductionCompany.new
  end

  def set_current
    production_company = Current.user.production_companies.find(params[:id])

    # Proceed with setting the new production company
    user_id = Current.user&.id
    if user_id
      session[:current_production_company_id] ||= {}
      session[:current_production_company_id]["#{user_id}"] = production_company.id
    end
    redirect_to manage_path
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_production_company
      @production_company = ProductionCompany.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def production_company_params
      params.expect(production_company: [ :name ])
    end
end

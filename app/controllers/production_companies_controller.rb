class ProductionCompaniesController < ApplicationController
  before_action :set_production_company, only: %i[ show edit update destroy ]

  def new
    @production_company = ProductionCompany.new
  end

  def edit
  end

  def create
    @production_company = ProductionCompany.new(production_company_params)
    @production_company.users << Current.user

    if @production_company.save
      session[:current_production_company_id] = @production_company.id
      redirect_to dashboard_path, notice: "Production company was successfully created."
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
  end

  def set_current
    production_company = Current.user.production_companies.find(params[:id])
    session[:current_production_company_id] = production_company.id
    redirect_to dashboard_path
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

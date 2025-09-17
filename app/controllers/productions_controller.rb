class ProductionsController < ApplicationController
  before_action :set_production, only: %i[ show edit update destroy ]

  # GET /productions
  def index
    @productions = Current.production_company.present? ? Current.production_company.productions : Production.none
  end

  # GET /productions/1
  def show
    session[:production] = @production.id
  end

  # GET /productions/new
  def new
    @production = Production.new
  end

  # GET /productions/1/edit
  def edit
  end

  # POST /productions
  def create
    @production = Production.new(production_params)

    if @production.save
      redirect_to @production, notice: "Production was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /productions/1
  def update
    if @production.update(production_params)
      redirect_to @production, notice: "Production was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /productions/1
  def destroy
    @production.destroy!
    redirect_to productions_path, notice: "Production was successfully destroyed.", status: :see_other
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_production
      @production = Current.production_company.productions.find_by(id: params[:id])
      unless @production
        redirect_to productions_path, alert: "Not authorized or not found."
      end
    end

    # Only allow a list of trusted parameters through.
    def production_params
      params.require(:production).permit(:name, :description).merge(production_company_id: Current.production_company&.id)
    end
end

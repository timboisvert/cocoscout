class ProductionsController < ApplicationController
  before_action :set_production, only: %i[ show edit update destroy ]

  def index
    @productions = Current.production_company.present? ? Current.production_company.productions : Production.none
  end

  def show
    set_production_in_session
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
      redirect_to @production, notice: "Production was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @production.update(production_params)
      set_production_in_session
      redirect_to @production, notice: "Production was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if Current.production_company && Current.user
      session[:current_production_id_for_company]["#{Current.user&.id}_#{Current.production_company&.id}"] = nil
      @production.destroy!
      redirect_to productions_path, notice: "Production was successfully destroyed.", status: :see_other
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_production
      @production = Current.production_company.productions.find_by(id: params[:id])
      unless @production
        redirect_to productions_path, alert: "Not authorized or not found."
      end
    end

    def set_production_in_session
      # Set the current production in session for the current production company
      if Current.production_company && Current.user
        session[:current_production_id_for_company] ||= {}
        session[:current_production_id_for_company]["#{Current.user&.id}_#{Current.production_company&.id}"] = @production.id
      end
    end

    # Only allow a list of trusted parameters through.
    def production_params
      params.require(:production).permit(:name, :description).merge(production_company_id: Current.production_company&.id)
    end
end

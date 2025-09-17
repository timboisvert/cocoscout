class ApplicationController < ActionController::Base
  include Authentication

  before_action :hide_sidebar
  before_action :set_current_production_company, if: -> { Current.user.present? }
  before_action :set_current_production, if: -> { Current.user.present? }
  before_action :require_current_production_company, if: -> { Current.user.present? }

  def set_current_production
    if Current.production_company && session[:current_production_id_for_company].is_a?(Hash)
      prod_id = session[:current_production_id_for_company][Current.production_company.id.to_s] || session[:current_production_id_for_company][Current.production_company.id]
      if prod_id
        Current.production = Current.production_company.productions.find_by(id: prod_id)
      else
        Current.production = nil
      end
    else
      Current.production = nil
    end
  end

  def require_current_production_company
    return if controller_name == "home"
    return if controller_name == "production_companies" && %w[select set_current].include?(action_name)
    unless Current.production_company
      redirect_to select_production_companies_path
    end
  end

  private

  def hide_sidebar
    if controller_name == "sessions"
      @hide_sidebar = true
    elsif controller_name == "production_companies"
      @hide_sidebar = true
    else
      @hide_sidebar = false
    end
  end

  def set_current_production_company
    if session[:current_production_company_id]
      Current.production_company = ProductionCompany.find_by(id: session[:current_production_company_id])
    elsif Current.user && Current.user.production_companies.count == 1
      company = Current.user.production_companies.first
      session[:current_production_company_id] = company.id
      Current.production_company = company
    else
      Current.production_company = nil
    end
  end
end

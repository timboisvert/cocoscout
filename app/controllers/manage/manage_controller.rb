class Manage::ManageController < ActionController::Base
  include Authentication

  layout "application"

  # before_action :hide_sidebar
  before_action :set_current_production_company, if: -> { Current.user.present? }
  before_action :set_current_production, if: -> { Current.user.present? }
  before_action :require_current_production_company, if: -> { Current.user.present? }

  before_action :show_manage_sidebar

  def index
    if (production = Current.production)
      redirect_to manage_production_path(production)
    end
  end

  private

  def show_manage_sidebar
    @show_manage_sidebar = true
  end

  def set_current_production_company
    user_id = Current.user&.id
    if user_id && session[:current_production_company_id].is_a?(Hash)
      company_id = session[:current_production_company_id]["#{user_id}"]
      Current.production_company = ProductionCompany.find_by(id: company_id)
    elsif Current.user && Current.user.production_companies.count == 1
      company = Current.user.production_companies.first
      session[:current_production_company_id] ||= {}
      session[:current_production_company_id]["#{Current.user.id}"] = company.id
      Current.production_company = company
    else
      Current.production_company = nil
    end
  end

  def set_current_production
    user_id = Current.user&.id
    if user_id && Current.production_company && session[:current_production_id_for_company].is_a?(Hash)
      prod_id = session[:current_production_id_for_company]["#{user_id}_#{Current.production_company.id}"]
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
    return if controller_name == "locations"
    return if controller_name == "production_companies" && %w[new create select set_current].include?(action_name)
    unless Current.production_company
      redirect_to select_manage_production_companies_path
    end
  end
end

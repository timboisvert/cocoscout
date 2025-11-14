class Manage::ManageController < ActionController::Base
  include Authentication
  include Pagy::Method

  layout "application"

  # before_action :hide_sidebar
  before_action :set_current_organization, if: -> { Current.user.present? }
  before_action :set_current_production, if: -> { Current.user.present? }
  before_action :require_current_organization, if: -> { Current.user.present? }
  before_action :ensure_user_has_access_to_company, if: -> { Current.user.present? && Current.organization.present? }, except: [ :index ]
  before_action :ensure_user_has_access_to_production, if: -> { Current.user.present? }

  before_action :track_last_dashboard
  before_action :show_manage_sidebar

  def index
    # Explicitly ensure cookie is set before any redirect
    cookies.encrypted[:last_dashboard] = { value: "manage", expires: 1.year.from_now }
    Rails.logger.info "🔍 Index action - Forcing last_dashboard cookie to 'manage'"

    if (production = Current.production)
      redirect_to manage_production_path(production)
    else
      # Redirect to production selection
      redirect_to select_production_path
    end
  end

  def ensure_user_is_manager
    # Check if we're in a production-specific context
    production = instance_variable_get(:@production) || Current.production

    if production
      # Check production-specific permission
      unless Current.user&.manager_for_production?(production)
        redirect_to manage_path, notice: "You do not have permission to access that page."
      end
    else
      # Fall back to checking default role for production company
      unless Current.user&.manager?
        redirect_to manage_path, notice: "You do not have permission to access that page."
      end
    end
  end

  def ensure_user_is_global_manager
    # Only check global manager role, not production-specific permissions
    # Used for production-company level resources (people, team, locations)
    unless Current.user&.manager?
      redirect_to manage_path, notice: "You do not have permission to access that page."
    end
  end

  def track_last_dashboard
    cookies.encrypted[:last_dashboard] = { value: "manage", expires: 1.year.from_now }
  end

  def ensure_user_has_access_to_company
    # Ensure user has at least some role/access to the current production company
    unless Current.user&.has_access_to_current_company?
      redirect_to my_dashboard_path, alert: "You do not have access to this production company."
    end
  end

  def ensure_user_has_access_to_production
    # Ensure user has access to the current production
    # This checks if @production or Current.production is in the user's accessible productions
    production = instance_variable_get(:@production) || Current.production
    return unless production

    unless Current.user.accessible_productions.include?(production)
      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end
  end

  def check_production_access
    # Explicit check for @production after it's been set in child controller
    unless Current.user.accessible_productions.include?(@production)
      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end
  end

  private

  def show_manage_sidebar
    @show_manage_sidebar = true
  end

  def set_current_organization
    user_id = Current.user&.id
    if user_id && session[:current_organization_id].is_a?(Hash)
      company_id = session[:current_organization_id]["#{user_id}"]
      Current.organization = Organization.find_by(id: company_id)
    elsif Current.user && Current.user.organizations.count == 1
      company = Current.user.organizations.first
      session[:current_organization_id] ||= {}
      session[:current_organization_id]["#{Current.user.id}"] = company.id
      Current.organization = company
    else
      Current.organization = nil
    end
  end

  def set_current_production
    user_id = Current.user&.id
    if user_id && Current.organization && session[:current_production_id_for_organization].is_a?(Hash)
      prod_id = session[:current_production_id_for_organization]["#{user_id}_#{Current.organization.id}"]
      if prod_id
        Current.production = Current.organization.productions.find_by(id: prod_id)
      else
        Current.production = nil
      end
    else
      Current.production = nil
    end

    # Auto-select if user has exactly one accessible production
    if Current.production.nil? && Current.user && Current.organization
      accessible_productions = Current.user.accessible_productions.where(organization: Current.organization)
      if accessible_productions.count == 1
        production = accessible_productions.first
        session[:current_production_id_for_organization] ||= {}
        session[:current_production_id_for_organization]["#{user_id}_#{Current.organization.id}"] = production.id
        Current.production = production
      end
    end
  end

  def require_current_organization
    return if controller_name == "organizations" && %w[new create index show].include?(action_name)
    return if controller_name == "select"
    unless Current.organization
      redirect_to select_organization_path
    end
  end
end

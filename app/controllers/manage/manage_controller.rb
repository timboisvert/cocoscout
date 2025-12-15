# frozen_string_literal: true

module Manage
  class ManageController < ActionController::Base
    include Authentication
    include Pagy::Method

    layout "application"

    # before_action :hide_sidebar
    before_action :set_current_organization, if: -> { Current.user.present? }
    before_action :set_current_production, if: -> { Current.user.present? }
    before_action :require_current_organization, if: lambda {
      Current.user.present?
    }, except: %i[index welcome dismiss_production_welcome]
    before_action :ensure_user_has_access_to_company, if: lambda {
      Current.user.present? && Current.organization.present?
    }, except: %i[index welcome dismiss_production_welcome]
    before_action :ensure_user_has_access_to_production, if: -> { Current.user.present? }

    before_action :track_last_dashboard
    before_action :show_manage_sidebar

    def index
      # Check if user needs to see welcome page (but not when impersonating)
      if Current.user.welcomed_production_at.nil? && session[:user_doing_the_impersonating].blank?
        @show_manage_sidebar = false
        @has_organization = Current.user.organizations.any?
        @has_production = @has_organization && Current.organization&.productions&.any?
        @current_org = Current.organization
        @user_orgs = Current.user.organizations.includes(:organization_roles).order(:name)
        render "welcome" and return
      end

      # Explicitly ensure cookie is set before any redirect
      if Current.user.present?
        last_dashboard_prefs = cookies.encrypted[:last_dashboard]
        # Reset if it's an old string value instead of a hash
        last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
        last_dashboard_prefs[Current.user.id.to_s] = "manage"
        cookies.encrypted[:last_dashboard] = { value: last_dashboard_prefs, expires: 1.year.from_now }
        Rails.logger.info "🔍 Index action - Forcing last_dashboard cookie to 'manage' for user #{Current.user.id}"
      end

      if (production = Current.production)
        redirect_to manage_production_path(production)
      else
        # Redirect to production selection
        redirect_to select_production_path
      end
    end

    def welcome
      @show_manage_sidebar = false
      @has_organization = Current.user.organizations.any?
      @has_production = @has_organization && Current.organization&.productions&.any?
      @current_org = Current.organization
      @user_orgs = Current.user.organizations.includes(:organization_roles).order(:name)
      render "welcome"
    end

    def dismiss_production_welcome
      # Prevent dismissing welcome screen when impersonating
      if session[:user_doing_the_impersonating].present?
        redirect_to manage_path, alert: "Cannot dismiss welcome screen while impersonating"
        return
      end

      Current.user.update(welcomed_production_at: Time.current)

      # Redirect to shows page if we have a production, otherwise to manage path
      if Current.production.present?
        redirect_to manage_production_shows_path(Current.production)
      else
        redirect_to manage_path
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
        redirect_to manage_path, notice: "You do not have permission to access that page." unless Current.user&.manager?
      end
    end

    def ensure_user_is_global_manager
      # Only check global manager role, not production-specific permissions
      # Used for production-company level resources (people, team, locations)
      return if Current.user&.manager?

      redirect_to manage_path, notice: "You do not have permission to access that page."
    end

    def track_last_dashboard
      return unless Current.user.present?

      last_dashboard_prefs = cookies.encrypted[:last_dashboard]
      # Reset if it's an old string value instead of a hash
      last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
      last_dashboard_prefs[Current.user.id.to_s] = "manage"
      cookies.encrypted[:last_dashboard] = { value: last_dashboard_prefs, expires: 1.year.from_now }
    end

    def ensure_user_has_access_to_company
      # Ensure user has at least some role/access to the current production company
      return if Current.user&.has_access_to_current_company?

      redirect_to my_dashboard_path, alert: "You do not have access to this production company."
    end

    def ensure_user_has_access_to_production
      # Ensure user has access to the current production
      # This checks if @production or Current.production is in the user's accessible productions
      production = instance_variable_get(:@production) || Current.production
      return unless production

      return if Current.user.accessible_productions.include?(production)

      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end

    def check_production_access
      # Explicit check for @production after it's been set in child controller
      return if Current.user.accessible_productions.include?(@production)

      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end

    private

    def show_manage_sidebar
      @show_manage_sidebar = true
    end

    def set_current_organization
      user_id = Current.user&.id
      if user_id && session[:current_organization_id].is_a?(Hash)
        company_id = session[:current_organization_id][user_id.to_s]
        Current.organization = Organization.find_by(id: company_id)
      elsif Current.user && Current.user.organizations.count == 1
        company = Current.user.organizations.first
        session[:current_organization_id] ||= {}
        session[:current_organization_id][Current.user.id.to_s] = company.id
        Current.organization = company
      else
        Current.organization = nil
      end
    end

    def set_current_production
      user_id = Current.user&.id
      if user_id && Current.organization && session[:current_production_id_for_organization].is_a?(Hash)
        prod_id = session[:current_production_id_for_organization]["#{user_id}_#{Current.organization.id}"]
        Current.production = if prod_id
                               Current.organization.productions.includes(logo_attachment: :blob).find_by(id: prod_id)
        end
      else
        Current.production = nil
      end

      # Auto-select if user has exactly one accessible production
      return unless Current.production.nil? && Current.user && Current.organization

      accessible_productions = Current.user.accessible_productions.where(organization: Current.organization)
      return unless accessible_productions.count == 1

      production = accessible_productions.first
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{user_id}_#{Current.organization.id}"] = production.id
      Current.production = production
    end

    def require_current_organization
      return if controller_name == "organizations" && %w[new create index show].include?(action_name)
      return if controller_name == "select"

      return if Current.organization

      redirect_to select_organization_path
    end

    # Shared data fetchers for use across controllers
    def fetch_locations
      Rails.cache.fetch(locations_cache_key, expires_in: 10.minutes) do
        Current.organization.locations.order(:created_at).to_a
      end
    end

    def locations_cache_key
      max_updated = Current.organization.locations.maximum(:updated_at)
      [ "locations_v1", Current.organization.id, max_updated ]
    end

    def fetch_team_members
      Rails.cache.fetch(team_cache_key, expires_in: 10.minutes) do
        members = Current.organization.users
                         .joins(:organization_roles)
                         .includes(:person, :organization_roles)
                         .where(organization_roles: { organization_id: Current.organization.id,
                                                      company_role: %w[manager viewer member] })
                         .distinct
        members.sort_by { |user| user == Current.user ? [ 0, "" ] : [ 1, user.email_address.downcase ] }
      end
    end

    def team_cache_key
      max_role_updated = OrganizationRole.where(organization: Current.organization).maximum(:updated_at)
      max_user_updated = Current.organization.users.maximum(:updated_at)
      [ "team_members_v1", Current.organization.id, Current.user.id, max_role_updated, max_user_updated ]
    end
  end
end

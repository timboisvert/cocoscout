# frozen_string_literal: true

module Manage
  class SelectController < Manage::ManageController
    before_action :set_current_organization, except: %i[organization set_organization]
    skip_before_action :show_manage_sidebar
    before_action :show_manage_header_only
    before_action :hide_production_selector

    def organization
      # Organization selection screen
      @organizations = Current.user.organizations.includes(:owner, :productions, :users).order(:name)

      # If user has only one organization, auto-select it and redirect to manage
      if @organizations.size == 1
        organization = @organizations.first
        user_id = Current.user&.id
        if user_id
          session[:current_organization_id] ||= {}
          session[:current_organization_id][user_id.to_s] = organization.id
        end
        redirect_to manage_path
        return
      end

      # Add role information for each organization
      @organization_roles = {}
      @organizations.each do |org|
        @organization_roles[org.id] = org.role_for(Current.user)
      end

      @organization = Organization.new
    end

    def set_organization
      organization = Current.user.organizations.find(params[:id])

      # Set the organization in session using the same format as set_current_organization
      user_id = Current.user&.id
      if user_id
        session[:current_organization_id] ||= {}
        session[:current_organization_id][user_id.to_s] = organization.id
      end

      # Always redirect to manage - production auto-selection happens there if needed
      redirect_to manage_path
    end

    private

    def hide_production_selector
      @hide_production_selector = true
    end
  end
end

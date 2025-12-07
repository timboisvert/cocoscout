# frozen_string_literal: true

module Manage
  class SelectController < Manage::ManageController
    before_action :set_current_organization, except: %i[organization set_organization]
    skip_before_action :show_manage_sidebar

    def organization
      # Organization selection screen
      @organizations = Current.user.organizations.includes(:owner, :productions, :users).order(:name)

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

      # Check if user has a production saved for this organization
      production_key = "#{user_id}_#{organization.id}"
      has_saved_production = session[:current_production_id_for_organization]&.key?(production_key)

      if has_saved_production
        redirect_to manage_path
      else
        redirect_to select_production_path
      end
    end

    def production
      # Production selection screen
      # If no organization in session, redirect to organization selection
      if Current.organization.nil?
        redirect_to select_organization_path, alert: "Please select an organization first"
        return
      end

      @productions = Current.user.accessible_productions.where(organization: Current.organization).order(:name)

      # If user has exactly one production, auto-select it
      if @productions.count == 1
        production = @productions.first
        session[:current_production_id_for_organization] ||= {}
        session[:current_production_id_for_organization]["#{Current.user.id}_#{Current.organization.id}"] =
          production.id
        redirect_to manage_path
        return
      end

      @production = Production.new
    end

    def set_production
      production = Current.organization.productions.find(params[:id])
      unless Current.user.accessible_productions.include?(production)
        redirect_to select_production_path, alert: "You do not have access to this production."
        return
      end

      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user.id}_#{Current.organization.id}"] = production.id
      redirect_to manage_path
    end
  end
end

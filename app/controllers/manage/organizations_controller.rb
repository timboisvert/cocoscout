# frozen_string_literal: true

module Manage
  class OrganizationsController < Manage::ManageController
    before_action :set_organization, only: %i[show edit update destroy transfer_ownership remove_logo confirm_delete]
    skip_before_action :show_manage_sidebar, only: %i[new create index edit]
    before_action :ensure_user_is_owner, only: %i[destroy transfer_ownership confirm_delete]
    before_action :ensure_user_can_manage, only: %i[show edit update remove_logo]

    def index
      # Management screen - list all organizations with management options
      @organizations = Current.user.organizations.includes(:owner, :productions, :users).order(:name)

      # Add role information for each organization
      @organization_roles = {}
      @organizations.each do |org|
        @organization_roles[org.id] = org.role_for(Current.user)
      end
    end

    def show
      @role = @organization.role_for(Current.user)
      @is_owner = @organization.owned_by?(Current.user)
      @team_members = @organization.users.includes(:default_person, :organization_roles)
      @team_invitations = @organization.team_invitations.where(accepted_at: nil, production_id: nil)
      @locations = @organization.locations.order(:created_at)
      @team_invitation = TeamInvitation.new
      @productions = @organization.productions.order(:name)
      @agreement_templates = @organization.agreement_templates.order(:name)
    end

    def new
      @organization = Organization.new
    end

    def edit; end

    def create
      @organization = Organization.new(organization_params)
      @organization.owner = Current.user

      if @organization.save
        # Assign creator as manager via organization role
        OrganizationRole.create!(user: Current.user, organization: @organization, company_role: "manager")

        # Ensure user has a person record and it's associated with this organization
        if Current.user.person.nil?
          person = Person.create!(
            email: Current.user.email_address,
            first_name: Current.user.email_address.split("@").first.titleize,
            last_name: ""
          )
          Current.user.update(person: person)
        end

        # Associate the person with the organization if not already
        @organization.people << Current.user.person unless @organization.people.include?(Current.user.person)

        # Set as current organization
        session[:current_organization_id] ||= {}
        session[:current_organization_id][Current.user&.id.to_s] = @organization.id

        redirect_to manage_path, notice: "#{@organization.name} was successfully created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @organization.update(organization_params)
        redirect_to manage_organization_path(@organization), notice: "Organization was successfully updated",
                                                             status: :see_other
      else
        # Re-setup show page instance variables for rendering
        @role = @organization.role_for(Current.user)
        @is_owner = @organization.owned_by?(Current.user)
        @team_members = @organization.users.includes(:default_person, :organization_roles)
        @team_invitations = @organization.team_invitations.where(accepted_at: nil, production_id: nil)
        @locations = @organization.locations.order(:created_at)
        @team_invitation = TeamInvitation.new
        @productions = @organization.productions.order(:name)
        @agreement_templates = @organization.agreement_templates.order(:name)
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      name = @organization.name
      @organization.destroy!

      # Clear from session if it was current
      session[:current_organization_id]&.delete(Current.user.id.to_s)

      redirect_to manage_organizations_path, notice: "#{name} was successfully deleted", status: :see_other
    end

    def remove_logo
      @organization.logo.purge
      redirect_back fallback_location: manage_organization_path(@organization), notice: "Logo removed successfully"
    end

    def confirm_delete
      @stats = {
        productions: @organization.productions.count,
        shows: @organization.productions.joins(:shows).count,
        people: @organization.people.count,
        groups: @organization.groups.count,
        locations: @organization.locations.count,
        team_members: @organization.users.count
      }
    end

    def set_current
      organization = Current.user.organizations.find(params[:id])

      # Proceed with setting the new organization
      user_id = Current.user&.id
      if user_id
        session[:current_organization_id] ||= {}
        session[:current_organization_id][user_id.to_s] = organization.id

        # Clear organization specific session filters/settings
        session.delete(:people_order)
        session.delete(:people_show)
        session.delete(:people_filter)
      end
      redirect_to manage_path
    end

    def transfer_ownership
      new_owner = User.find(params[:new_owner_id])

      # Ensure new owner has manager role
      unless @organization.organization_roles.exists?(user: new_owner, company_role: "manager")
        redirect_to manage_organization_path(@organization), alert: "New owner must be a manager first"
        return
      end

      @organization.update!(owner: new_owner)
      redirect_to manage_organization_path(@organization),
                  notice: "Ownership transferred to #{new_owner.person&.name || new_owner.email_address}"
    end

    def setup_guide; end

    private

    def set_organization
      @organization = Organization.find(params[:id])
    end

    def organization_params
      params.expect(organization: %i[name logo])
    end

    def ensure_user_is_owner
      return if @organization.owned_by?(Current.user)

      redirect_to manage_organizations_path, alert: "Only the owner can perform this action"
    end

    def ensure_user_can_manage
      return if @organization.manageable_by?(Current.user)

      redirect_to manage_organizations_path, alert: "You don't have permission to manage this organization"
    end
  end
end

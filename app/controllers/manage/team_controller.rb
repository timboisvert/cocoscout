# frozen_string_literal: true

module Manage
  class TeamController < Manage::ManageController
    before_action :ensure_user_is_global_manager, except: %i[index]

    def index
      # Redirect to organization settings page with team tab
      redirect_to manage_organization_path(Current.organization, anchor: "tab-1")
    end

    def check_profiles
      email = params[:email]&.strip&.downcase
      return render json: { profiles: [] } if email.blank?

      profiles = Person.where(email: email).map do |p|
        {
          id: p.id,
          name: p.name,
          organizations: p.organizations.pluck(:name),
          already_in_org: p.organizations.include?(Current.organization)
        }
      end

      render json: { profiles: profiles }
    end

    def invite
      @team_invitation = TeamInvitation.new(team_invitation_params)
      @team_invitation.organization = Current.organization

      # If a person_id was provided, use that profile
      if params[:team_invitation][:person_id].present?
        @team_invitation.person_id = params[:team_invitation][:person_id]
      end

      default_subject = ContentTemplateService.render_subject("team_invitation", {
        organization_name: Current.organization.name
      })
      default_message = ContentTemplateService.render_body("team_invitation", {
        organization_name: Current.organization.name,
        accept_url: "[accept link will be included]"
      })

      invitation_subject = params[:team_invitation][:invitation_subject] || default_subject
      invitation_message = params[:team_invitation][:invitation_message] || default_message

      if @team_invitation.save
        expire_team_cache
        Manage::TeamMailer.invite(@team_invitation, invitation_subject, invitation_message).deliver_later
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), notice: "Invitation sent"
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                    alert: "Could not send invitation. Please check the email address."
      end
    end

    def update_role
      user = Current.organization.users.find(params[:id])
      role = params[:role]
      organization_role = OrganizationRole.find_by(user: user, organization: Current.organization)
      if organization_role && %w[manager viewer none].include?(role)
        organization_role.update(company_role: role)
        expire_team_cache
        respond_to do |format|
          format.json { render json: { success: true } }
          format.html { redirect_to manage_team_index_path, notice: "Role updated" }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html { redirect_to manage_team_index_path, alert: "Could not update role" }
        end
      end
    end

    def revoke_invite
      team_invitation = Current.organization.team_invitations.find_by(id: params[:id], accepted_at: nil)
      if team_invitation
        team_invitation.destroy
        expire_team_cache
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), notice: "Invitation revoked"
      else
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                    alert: "Invitation not found or already accepted"
      end
    end

    def remove_member
      user = Current.organization.users.find_by(id: params[:id])
      if user && user != Current.user
        organization_role = OrganizationRole.find_by(user: user, organization: Current.organization)
        if organization_role
          organization_role.destroy
          expire_team_cache
          respond_to do |format|
            format.json { render json: { success: true } }
            format.html do
              redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), notice: "Team member removed"
            end
          end
        else
          respond_to do |format|
            format.json { render json: { success: false }, status: :unprocessable_entity }
            format.html do
              redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                          alert: "Could not remove Team member"
            end
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                        alert: "Unable to remove team member"
          end
        end
      end
    end

    def permissions
      @user = Current.organization.users.find(params[:id])

      # Don't let users access their own permissions page
      if @user == Current.user
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                    alert: "You cannot manage your own permissions."
        return
      end

      @productions = Current.organization.productions.order(:name)
      @organization_role = @user.organization_roles.find_by(organization: Current.organization)

      # Render partial for AJAX/modal requests
      if request.xhr? || request.headers["X-Requested-With"] == "XMLHttpRequest"
        render partial: "manage/productions/permissions_content",
               locals: { user: @user, productions: @productions, organization_role: @organization_role }, layout: false
      else
        # Redirect to organization settings with team tab for direct access
        redirect_to manage_organization_path(Current.organization, anchor: "tab-1")
      end
    end

    def update_production_permission
      user = Current.organization.users.find(params[:id])
      production = Current.organization.productions.find(params[:production_id])
      role = params[:role]

      if role.blank? || role == "default"
        # Remove production-specific permission to use default role
        permission = ProductionPermission.find_by(user: user, production: production)
        permission&.destroy
        message = "Using global role for #{production.name}"
      elsif %w[manager viewer].include?(role)
        # Set or update production-specific permission
        permission = ProductionPermission.find_or_initialize_by(user: user, production: production)
        permission.role = role
        if permission.save
          message = "Role updated for #{production.name}"
        else
          respond_to do |format|
            format.json do
              render json: { success: false, error: permission.errors.full_messages.join(", ") },
                     status: :unprocessable_entity
            end
            format.html do
              redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                          alert: "Could not update role"
            end
          end
          return
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), alert: "Invalid role"
          end
        end
        return
      end

      expire_team_cache
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), notice: message }
      end
    end

    def update_production_notifications
      user = Current.organization.users.find(params[:id])
      production = Current.organization.productions.find(params[:production_id])
      notifications_enabled = params[:notifications_enabled] == "1"

      # Find or create the production permission
      permission = ProductionPermission.find_by(user: user, production: production)

      if permission
        # Update existing permission
        permission.update!(notifications_enabled: notifications_enabled)
      else
        # User has access via global role, create a permission record just for notifications
        effective_role = user.role_for_production(production)
        if effective_role.present? && effective_role != "none"
          ProductionPermission.create!(
            user: user,
            production: production,
            role: effective_role,
            notifications_enabled: notifications_enabled
          )
        end
      end

      expire_team_cache
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to manage_organization_path(Current.organization, anchor: "tab-1"), notice: "Notification preference updated" }
      end
    end

    def update_global_role
      user = Current.organization.users.find(params[:id])
      role = params[:global_role]
      organization_role = OrganizationRole.find_by(user: user, organization: Current.organization)

      if organization_role && %w[manager viewer none].include?(role)
        organization_role.update(company_role: role)
        expire_team_cache
        role_display = case role
        when "manager" then "Manager"
        when "viewer" then "Viewer"
        when "none" then "None"
        end
        respond_to do |format|
          format.json { render json: { success: true } }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                        notice: "Global role updated to #{role_display}"
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                        alert: "Could not update global role"
          end
        end
      end
    end

    def update_global_notifications
      user = Current.organization.users.find(params[:id])
      organization_role = OrganizationRole.find_by(user: user, organization: Current.organization)

      if organization_role
        notifications_enabled = params[:notifications_enabled] == "1"
        organization_role.update(notifications_enabled: notifications_enabled)
        expire_team_cache
        respond_to do |format|
          format.json { render json: { success: true } }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                        notice: "Notification preference updated"
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html do
            redirect_to manage_organization_path(Current.organization, anchor: "tab-1"),
                        alert: "Could not update notification preference"
          end
        end
      end
    end

    private

    def fetch_team_members
      Rails.cache.fetch(team_cache_key, expires_in: 10.minutes) do
        members = Current.organization.users
                         .joins(:organization_roles)
                         .includes(:default_person, :organization_roles)
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

    def expire_team_cache
      Rails.cache.delete(team_cache_key)
    end

    def team_invitation_params
      params.require(:team_invitation).permit(:email)
    end
  end
end

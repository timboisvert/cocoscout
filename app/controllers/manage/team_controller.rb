 class Manage::TeamController < Manage::ManageController
  before_action :ensure_user_is_global_manager, except: %i[index]

  def index
    # Redirect to production settings page with team tab
    if Current.production
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3")
    else
      redirect_to manage_path
    end
  end

  def invite
    @team_invitation = TeamInvitation.new(team_invitation_params)
    @team_invitation.organization = Current.organization

    invitation_subject = params[:team_invitation][:invitation_subject] || "You've been invited to join #{Current.organization.name}'s team on CocoScout"
    invitation_message = params[:team_invitation][:invitation_message] || "Welcome to CocoScout!\n\n#{Current.organization.name} is using CocoScout to manage its productions. You've been invited to join the team.\n\nClick the link below to accept the invitation and sign in or create an account."

    if @team_invitation.save
      expire_team_cache
      Manage::TeamMailer.invite(@team_invitation, invitation_subject, invitation_message).deliver_later
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), notice: "Invitation sent"
    else
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Could not send invitation. Please check the email address."
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
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), notice: "Invitation revoked"
    else
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Invitation not found or already accepted"
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
          format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), notice: "Team member removed" }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Could not remove Team member" }
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Unable to remove team member" }
      end
    end
  end

  def permissions
    @user = Current.organization.users.find(params[:id])

    # Don't let users access their own permissions page
    if @user == Current.user
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "You cannot manage your own permissions."
      return
    end

    @productions = Current.organization.productions.order(:name)
    @organization_role = @user.organization_roles.find_by(organization: Current.organization)

    # Render partial for AJAX/modal requests
    if request.xhr? || request.headers["X-Requested-With"] == "XMLHttpRequest"
      render partial: "manage/productions/permissions_content", locals: { user: @user, productions: @productions, organization_role: @organization_role }, layout: false
    else
      # Redirect to production edit page with team tab for direct access
      redirect_to edit_manage_production_path(Current.production, anchor: "tab-3")
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
          format.json { render json: { success: false, error: permission.errors.full_messages.join(", ") }, status: :unprocessable_entity }
          format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Could not update role" }
        end
        return
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Invalid role" }
      end
      return
    end

    expire_team_cache
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), notice: message }
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
        format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), notice: "Global role updated to #{role_display}" }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to edit_manage_production_path(Current.production, anchor: "tab-3"), alert: "Could not update global role" }
      end
    end
  end


  private

  def fetch_team_members
    Rails.cache.fetch(team_cache_key, expires_in: 10.minutes) do
      members = Current.organization.users
        .joins(:organization_roles)
        .includes(:person, :organization_roles)
        .where(organization_roles: { organization_id: Current.organization.id, company_role: %w[manager viewer none] })
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

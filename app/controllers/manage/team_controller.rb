 class Manage::TeamController < Manage::ManageController
  before_action :ensure_user_is_global_manager, except: %i[index]

  def index
    members = Current.organization.users.joins(:user_roles).where(user_roles: { organization_id: Current.organization.id, company_role: [ "manager", "viewer", "none" ] }).distinct
    @members = members.sort_by { |user| user == Current.user ? [ 0, "" ] : [ 1, user.email_address.downcase ] }
    @team_invitation = Current.organization.team_invitations.new
    @team_invitations = Current.organization.team_invitations.where(accepted_at: nil)
  end

  def invite
    @team_invitation = TeamInvitation.new(team_invitation_params)
    @team_invitation.organization = Current.organization
    if @team_invitation.save
      Manage::TeamMailer.invite(@team_invitation).deliver_later
      redirect_to manage_team_index_path, notice: "Invitation sent"
    else
      members = Current.organization.users.joins(:user_roles).where(user_roles: { organization_id: Current.organization.id, company_role: [ "manager", "viewer", "none" ] }).distinct
      @members = members.sort_by { |user| user == Current.user ? [ 0, "" ] : [ 1, user.email_address.downcase ] }
      @team_invitation = Current.organization.team_invitations.new
      @team_invitations = Current.organization.team_invitations.where(accepted_at: nil)
      @team_invitation_error = true
      render :index, status: :unprocessable_entity
    end
  end

  def update_role
    user = Current.organization.users.find(params[:id])
    role = params[:role]
    user_role = UserRole.find_by(user: user, organization: Current.organization)
    if user_role && %w[manager viewer none].include?(role)
      user_role.update(company_role: role)
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
      redirect_to manage_team_index_path, notice: "Invitation revoked"
    else
      redirect_to manage_team_index_path, alert: "Invitation not found or already accepted"
    end
  end

  def remove_member
    user = Current.organization.users.find_by(id: params[:id])
    if user && user != Current.user
      user_role = UserRole.find_by(user: user, organization: Current.organization)
      if user_role
        user_role.destroy
        respond_to do |format|
          format.json { render json: { success: true } }
          format.html { redirect_to manage_team_index_path, notice: "Team member removed" }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html { redirect_to manage_team_index_path, alert: "Could not remove Team member" }
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to manage_team_index_path, alert: "Unable to remove team member" }
      end
    end
  end

  def permissions
    @user = Current.organization.users.find(params[:id])

    # Don't let users access their own permissions page
    if @user == Current.user
      redirect_to manage_team_index_path, alert: "You cannot manage your own permissions."
      return
    end

    @productions = Current.organization.productions.order(:name)
    @user_role = @user.user_roles.find_by(organization: Current.organization)
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
          format.html { redirect_to permissions_manage_team_path(user), alert: "Could not update role" }
        end
        return
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to permissions_manage_team_path(user), alert: "Invalid role" }
      end
      return
    end

    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to permissions_manage_team_path(user), notice: message }
    end
  end

  def update_global_role
    user = Current.organization.users.find(params[:id])
    role = params[:global_role]
    user_role = UserRole.find_by(user: user, organization: Current.organization)

    if user_role && %w[manager viewer none].include?(role)
      user_role.update(company_role: role)
      role_display = case role
      when "manager" then "Manager"
      when "viewer" then "Viewer"
      when "none" then "None"
      end
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to permissions_manage_team_path(user), notice: "Global role updated to #{role_display}" }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to permissions_manage_team_path(user), alert: "Could not update global role" }
      end
    end
  end


  private
  def team_invitation_params
    params.require(:team_invitation).permit(:email)
  end
 end

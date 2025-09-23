 class Manage::TeamController < Manage::ManageController
  def index
    @members = Current.production_company.users.joins(:user_roles).where(user_roles: { production_company_id: Current.production_company.id, role: [ "admin", "member" ] }).distinct
    @team_invitation = Current.production_company.team_invitations.new
    @team_invitations = Current.production_company.team_invitations.where(accepted_at: nil)
  end

  def invite
    @team_invitation = TeamInvitation.new(team_invitation_params)
    @team_invitation.production_company = Current.production_company
    if @team_invitation.save
      redirect_to manage_team_index_path, notice: "Invitation sent."
    else
      @members = Current.production_company.users.joins(:user_roles).where(user_roles: { production_company_id: Current.production_company.id, role: [ "admin", "member" ] }).distinct
      @team_invitation = Current.production_company.team_invitations.new
      @team_invitations = Current.production_company.team_invitations.where(accepted_at: nil)
      @team_invitation_error = true
      render :index, status: :unprocessable_entity
    end
  end

  def update_role
    user = Current.production_company.users.find(params[:id])
    role = params[:role]
    user_role = UserRole.find_by(user: user, production_company: Current.production_company)
    if user_role && %w[admin member].include?(role)
      user_role.update(role: role)
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to manage_team_index_path, notice: "Role updated." }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to manage_team_index_path, alert: "Could not update role." }
      end
    end
  end

  def revoke_invite
    team_invitation = Current.production_company.team_invitations.find_by(id: params[:id], accepted_at: nil)
    if team_invitation
      team_invitation.destroy
      redirect_to manage_team_index_path, notice: "Invitation revoked."
    else
      redirect_to manage_team_index_path, alert: "Invitation not found or already accepted."
    end
  end

  def remove_member
    user = Current.production_company.users.find_by(id: params[:id])
    if user && user != Current.user
      user_role = UserRole.find_by(user: user, production_company: Current.production_company)
      if user_role
        user_role.destroy
        respond_to do |format|
          format.json { render json: { success: true } }
          format.html { redirect_to manage_team_index_path, notice: "Team member removed." }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html { redirect_to manage_team_index_path, alert: "Could not remove team member." }
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to manage_team_index_path, alert: "You cannot remove yourself or user not found." }
      end
    end
  end


  private
  def team_invitation_params
    params.require(:team_invitation).permit(:email)
  end
 end

 class TeamController < ApplicationController
  def index
    @members = Current.production_company.users
    @invitation = Current.production_company.invitations.new
    @invitations = Current.production_company.invitations.where(accepted_at: nil)
  end

  def invite
    @invitation = Invitation.new(invitation_params)
    @invitation.production_company = Current.production_company
    if @invitation.save
      redirect_to team_index_path, notice: "Invitation sent."
    else
      @members = Current.production_company.users
      @invitation = Current.production_company.invitations.new
      @invitations = Current.production_company.invitations.where(accepted_at: nil)
      @invitation_error = true
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
        format.html { redirect_to team_index_path, notice: "Role updated." }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to team_index_path, alert: "Could not update role." }
      end
    end
  end

  def revoke_invite
    invitation = Current.production_company.invitations.find_by(id: params[:id], accepted_at: nil)
    if invitation
      invitation.destroy
      redirect_to team_index_path, notice: "Invitation revoked."
    else
      redirect_to team_index_path, alert: "Invitation not found or already accepted."
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
          format.html { redirect_to team_index_path, notice: "Team member removed." }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false }, status: :unprocessable_entity }
          format.html { redirect_to team_index_path, alert: "Could not remove team member." }
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false }, status: :unprocessable_entity }
        format.html { redirect_to team_index_path, alert: "You cannot remove yourself or user not found." }
      end
    end
  end


  private
  def invitation_params
    params.require(:invitation).permit(:email)
  end
 end

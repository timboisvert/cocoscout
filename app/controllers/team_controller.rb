class TeamController < ApplicationController
  def index
    @production_company = Current.production_company
    @members = @production_company.users
    @invitations = @production_company.invitations.where(accepted_at: nil)
  end

  def invite
    @invitation = Invitation.new(invitation_params)
    @invitation.production_company = Current.production_company
    if @invitation.save
      redirect_to team_index_path, notice: "Invitation sent."
    else
      redirect_to team_index_path, alert: @invitation.errors.full_messages.to_sentence
    end
  end

  def update_role
    user = Current.production_company.users.find(params[:id])
    role = params[:role]
    user_role = UserRole.find_by(user: user, production_company: Current.production_company)
    if user_role && %w[admin member].include?(role)
      user_role.update(role: role)
      redirect_to team_index_path, notice: "Role updated."
    else
      redirect_to team_index_path, alert: "Could not update role."
    end
  end

  private
  def invitation_params
    params.require(:invitation).permit(:email)
  end
end

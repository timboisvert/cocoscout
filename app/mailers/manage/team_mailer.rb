class Manage::TeamMailer < ApplicationMailer
  def invite(team_invitation)
    @team_invitation = team_invitation
    mail(to: @team_invitation.email, subject: "You've been invited to join #{@team_invitation.production_company.name}'s production team on CocoScout")
  end
end

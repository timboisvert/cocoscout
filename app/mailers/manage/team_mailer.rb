class Manage::TeamMailer < ApplicationMailer
  def invite(team_invitation, subject = nil, message = nil)
    @team_invitation = team_invitation
    @custom_message = message
    
    subject ||= "You've been invited to join #{team_invitation.organization.name}'s team on CocoScout"
    mail(to: @team_invitation.email, subject: subject)
  end
end

class TeamMailerPreview < ActionMailer::Preview
  def invite
    Manage::TeamMailer.invite(TeamInvitation.take)
  end
end

class GroupInvitationMailer < ApplicationMailer
  def invitation(group_invitation, subject = nil, message = nil)
    @invitation = group_invitation
    @token = group_invitation.token
    @group = group_invitation.group
    @custom_message = message
    @invited_by = group_invitation.invited_by

    subject ||= "You've been invited to join #{@group.name} on CocoScout"
    mail(to: @invitation.email, subject: subject)
  end

  def existing_member_added(person, group, invited_by, subject = nil, message = nil)
    @person = person
    @group = group
    @invited_by = invited_by
    @custom_message = message

    subject ||= "You've been added to #{@group.name} on CocoScout"
    mail(to: @person.email, subject: subject)
  end
end

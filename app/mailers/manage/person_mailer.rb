class Manage::PersonMailer < ApplicationMailer
  def person_invitation(person_invitation, subject = nil, message = nil)
    @person_invitation = person_invitation
    @token = person_invitation.token
    @organization = person_invitation.organization
    @custom_message = message

    subject ||= if @organization
      "You've been invited to join #{@organization.name} on CocoScout"
    else
      "You've been invited to join CocoScout"
    end

    mail(to: @person_invitation.email, subject: subject)
  end

  def contact_email(person, subject, message, sender)
    @person = person
    @subject = subject
    @message = message
    @sender = sender
    mail(to: person.email, subject: subject)
  end
end

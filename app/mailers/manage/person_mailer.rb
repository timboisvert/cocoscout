class Manage::PersonMailer < ApplicationMailer
  def person_invitation(person_invitation)
    @person_invitation = person_invitation
    @token = person_invitation.token
    @production_company = person_invitation.production_company
    mail(to: @person_invitation.email, subject: "You've been invited to join #{@production_company.name} on CocoScout")
  end

  def contact_email(person, subject, message, sender)
    @person = person
    @subject = subject
    @message = message
    @sender = sender
    mail(to: person.email, subject: subject)
  end
end

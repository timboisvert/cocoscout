class Manage::AuditionMailer < ApplicationMailer
  def casting_notification(person, production, email_body)
    @person = person
    @production = production
    @email_body = email_body

    mail(
      to: person.email,
      subject: "Audition Results for #{production.name}"
    )
  end

  def invitation_notification(person, production, email_body)
    @person = person
    @production = production
    @email_body = email_body

    mail(
      to: person.email,
      subject: "#{production.name} Auditions"
    )
  end
end

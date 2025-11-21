class Manage::CastingMailer < ApplicationMailer
  def cast_email(person, show, title, message, sender)
    @person = person
    @show = show
    @title = title
    @message = message
    @sender = sender
    mail(to: person.email, subject: title)
  end
end

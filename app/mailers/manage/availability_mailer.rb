class Manage::AvailabilityMailer < ApplicationMailer
  def request_availability(person, production, message)
    @person = person
    @production = production
    @message = message

    mail(to: person.email, subject: "Please submit your availability for #{production.name}")
  end
end

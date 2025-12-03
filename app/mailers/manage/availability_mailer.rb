class Manage::AvailabilityMailer < ApplicationMailer
  def request_availability(person, production, message)
    @person = person
    @production = production
    @message = message

    mail(to: person.email, subject: "Please submit your availability for #{production.name}")
  end

  def request_availability_for_group(group, production, message)
    @group = group
    @production = production
    @message = message

    mail(to: group.email, subject: "Please submit availability for #{group.name} - #{production.name}")
  end
end

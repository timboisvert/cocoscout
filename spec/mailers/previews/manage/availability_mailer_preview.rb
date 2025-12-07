# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/manage/availability_mailer
module Manage
  class AvailabilityMailerPreview < ActionMailer::Preview
    # Preview this email at http://localhost:3000/rails/mailers/manage/availability_mailer/request_availability
    def request_availability
      person = Person.first || Person.new(
        name: 'Jane Smith',
        email: 'jane@example.com'
      )
      production = Production.first || Production.new(name: 'The Music Man')
      message = "Please submit your availability for the following shows:\n\n- Friday, Nov 1 at 7:00 PM\n- Saturday, Nov 2 at 2:00 PM\n- Saturday, Nov 2 at 7:00 PM\n\nPlease let us know as soon as possible!"

      Manage::AvailabilityMailer.request_availability(person, production, message)
    end
  end
end

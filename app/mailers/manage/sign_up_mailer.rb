# frozen_string_literal: true

module Manage
  class SignUpMailer < ApplicationMailer
    def registration_notification(recipient_user, registration)
      @recipient = recipient_user
      @registration = registration
      @slot = registration.sign_up_slot
      @form = @slot.sign_up_form
      @production = @form.production
      @instance = @slot.sign_up_form_instance
      @show = @instance&.show

      # Get registrant name
      @registrant_name = registration.person&.name || registration.guest_name || "Guest"

      mail(
        to: recipient_user.email_address,
        subject: "[#{@production.name}] New sign-up from #{@registrant_name}"
      )
    end
  end
end

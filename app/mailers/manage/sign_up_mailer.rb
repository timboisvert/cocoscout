# frozen_string_literal: true

module Manage
  class SignUpMailer < ApplicationMailer
    # Called from SignUpProducerNotificationService with pre-rendered content
    def registration_notification
      @user = params[:user]
      @registration = params[:registration]
      @person = @user.person # For recipient entity tracking
      @subject = params[:subject]
      @body = params[:body]

      @slot = @registration.sign_up_slot
      @form = @slot.sign_up_form
      @production = @form.production

      mail(
        to: @user.email_address,
        subject: @subject
      )
    end
  end
end

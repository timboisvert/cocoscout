# frozen_string_literal: true

class MicSignupAlertMailer < ApplicationMailer
  def opens_soon(alert)
    @user = alert.user
    @mic  = alert.mic
    @signup_info = @mic.signup_info
    @lead_time_minutes = alert.lead_time_minutes

    mail(
      to: @user.email_address,
      subject: "Sign-up opens soon for #{@mic.name}"
    )
  end
end

# frozen_string_literal: true

class AuthMailer < ApplicationMailer
  def signup(user)
    @user = user
    @person = @user.person # For recipient entity tracking

    rendered = ContentTemplateService.render("auth_welcome", { user_email: user.email_address })
    @subject = rendered[:subject]
    @body = rendered[:body]

    mail(to: @user.email_address, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end

  def password(user, token)
    @user = user
    @person = @user.person # For recipient entity tracking
    @token = token

    reset_url = Rails.application.routes.url_helpers.reset_url(token, **default_url_options)
    rendered = ContentTemplateService.render("auth_password_reset", { reset_url: reset_url })
    @subject = rendered[:subject]
    @body = rendered[:body]

    mail(to: @user.email_address, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end
end

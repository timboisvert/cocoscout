# frozen_string_literal: true

class VacancyNotificationMailer < ApplicationMailer
  # Called from VacancyNotificationService with pre-rendered content
  def vacancy_notification
    @vacancy = params[:vacancy]
    @user = params[:user]
    @person = @user.person # For recipient entity tracking
    @event = params[:event]
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production

    # Use pre-rendered content from ContentTemplateService if provided
    @subject = params[:subject]
    @body = params[:body]

    mail(
      to: @user.email_address,
      subject: @subject
    )
  end
end

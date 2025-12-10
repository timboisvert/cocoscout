# frozen_string_literal: true

class VacancyNotificationMailer < ApplicationMailer
  def vacancy_notification
    @vacancy = params[:vacancy]
    @user = params[:user]
    @person = @user.person # For recipient entity tracking
    @event = params[:event]
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production

    subject = case @event
    when "created"
      "[#{@production.name}] New vacancy: #{@role.name} for #{@show.date_and_time.strftime('%b %-d')}"
    when "filled"
      "[#{@production.name}] Vacancy filled: #{@role.name} for #{@show.date_and_time.strftime('%b %-d')}"
    else
      "[#{@production.name}] Vacancy update: #{@role.name}"
    end

    mail(
      to: @user.email_address,
      subject: subject
    )
  end
end

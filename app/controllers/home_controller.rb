class HomeController < ApplicationController
  allow_unauthenticated_access

  # Use the public facing layout
  layout "home"

  def index
  end

  def notify_me
    email = params[:email]

    if email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      notify_me = NotifyMe.new(email: email)
      notify_me.save!
      redirect_to notify_me_success_path, status: :see_other
    else
      render :index, status: :unprocessable_entity
    end
  end

  def notify_me_success
  end
end

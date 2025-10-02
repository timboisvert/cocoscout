class UserMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    mail(to: @user.email_address, subject: "Welcome to CocoScout")
  end
end

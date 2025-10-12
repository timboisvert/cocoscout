class AuthMailer < ApplicationMailer
  def signup(user)
    @user = user
    mail(to: @user.email_address, subject: "Welcome to CocoScout")
  end

  def password_change_required(user)
    @user = user
    mail(to: @user.email_address, subject: "Action Required: Set your CocoScout password")
  end

  def password(user, token)
    @user = user
    @token = token
    mail(to: @user.email_address, subject: "Reset your CocoScout password")
  end
end

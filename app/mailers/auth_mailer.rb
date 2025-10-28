class AuthMailer < ApplicationMailer
  def signup(user)
    @user = user
    mail(to: @user.email_address, subject: "Welcome to CocoScout")
  end

  def invitation(user)
    @user = user
    @token = user.invitation_token
    mail(to: @user.email_address, subject: "You've been invited to join CocoScout")
  end

  def password(user, token)
    @user = user
    @token = token
    mail(to: @user.email_address, subject: "Reset your CocoScout password")
  end
end

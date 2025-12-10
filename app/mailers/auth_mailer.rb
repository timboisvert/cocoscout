# frozen_string_literal: true

class AuthMailer < ApplicationMailer
  def signup(user)
    @user = user
    @person = @user.person # For recipient entity tracking
    mail(to: @user.email_address, subject: "Welcome to CocoScout")
  end

  def password(user, token)
    @user = user
    @person = @user.person # For recipient entity tracking
    @token = token
    mail(to: @user.email_address, subject: "Reset your CocoScout password")
  end
end

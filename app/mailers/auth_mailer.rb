class AuthMailer < ApplicationMailer
  def signup(user)
    @user = user
    mail(to: @user.email_address, subject: "Welcome to CocoScout")
  end

  # DEPRECATED: Use person_invitation instead
  # Keeping for backwards compatibility
  def invitation(user)
    @user = user
    @token = user.invitation_token
    mail(to: @user.email_address, subject: "You've been invited to join CocoScout")
  end

  def person_invitation(person_invitation)
    @person_invitation = person_invitation
    @token = person_invitation.token
    @production_company = person_invitation.production_company
    mail(to: @person_invitation.email, subject: "You've been invited to join #{@production_company.name} on CocoScout")
  end

  def password(user, token)
    @user = user
    @token = token
    mail(to: @user.email_address, subject: "Reset your CocoScout password")
  end
end

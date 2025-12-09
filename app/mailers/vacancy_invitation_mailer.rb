# frozen_string_literal: true

class VacancyInvitationMailer < ApplicationMailer
  def invitation_email(invitation)
    @invitation = invitation
    @vacancy = invitation.role_vacancy
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production
    @person = invitation.person
    @claim_url = claim_vacancy_url(invitation.token)

    mail(
      to: @person.email,
      subject: invitation.email_subject || "You're invited to fill a role in #{@production.name}"
    )
  end
end

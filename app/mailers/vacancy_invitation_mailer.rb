# frozen_string_literal: true

class VacancyInvitationMailer < ApplicationMailer
  def invitation_email(invitation, email_batch_id: nil)
    @invitation = invitation
    @vacancy = invitation.role_vacancy
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production
    @person = invitation.person
    @claim_url = claim_vacancy_url(invitation.token)
    @email_batch_id = email_batch_id

    headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

    mail(
      to: @person.email,
      subject: invitation.email_subject || "You're invited to fill a role in #{@production.name}"
    )
  end

  private

  def find_email_batch_id
    @email_batch_id
  end
end

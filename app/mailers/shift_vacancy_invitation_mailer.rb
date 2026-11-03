# frozen_string_literal: true

# "Can you cover a shift?" (VacancyInvitationMailer's shape, for staff): the
# manager's words from the vacancy page with this person's claim link, by
# email and as an in-app message with no person attributed.
class ShiftVacancyInvitationMailer < ApplicationMailer
  def invitation_email(invitation, email_batch_id: nil)
    @invitation = invitation
    @vacancy = invitation.shift_vacancy
    @shift = @vacancy.shift
    @organization = @shift.organization
    @person = invitation.person
    @email_batch_id = email_batch_id

    variables = ShiftVacancyNotificationService.invitation_variables(@vacancy, person: @person, claim_url: claim_shift_url(invitation.token))
    rendered = ContentTemplateService.render("shift_vacancy_invitation", variables)
    @subject = invitation.email_subject.present? ? ContentTemplate.interpolate(invitation.email_subject, variables) : rendered[:subject]
    @body = invitation.email_body.present? ? ContentTemplate.interpolate(invitation.email_body, variables) : rendered[:body]

    headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?
    send_in_app_message(rendered.merge(subject: @subject, body: @body))
    return if @person.email.blank?

    mail(to: @person.email, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end

  private

  def send_in_app_message(rendered)
    return unless @person.user.present?

    MessageService.send_direct(
      template_key: "shift_vacancy_invitation", push_body: rendered[:push_body],
      sender: nil,
      recipient_person: @person,
      subject: rendered[:subject],
      body: rendered[:body],
      organization: @organization,
      system_generated: true
    )
  rescue => e
    Rails.logger.error("Failed to send shift cover invitation message: #{e.message}")
  end

  def find_email_batch_id
    @email_batch_id
  end
end

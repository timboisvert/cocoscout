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

    rendered = ContentTemplateService.render("vacancy_invitation", build_template_vars)

    @subject = invitation.email_subject.presence || rendered[:subject]
    @body = rendered[:body]

    headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

    # Also send in-app message since vacancy_invitation is channel "both"
    send_in_app_message(rendered)

    mail(to: @person.email, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end

  private

  def build_template_vars
    shows = if @show.linked? && @show.event_linkage.shows.count > 1
              @show.event_linkage.shows.order(:date_and_time).to_a
    else
              [ @show ]
    end

    shows_text = shows.map do |s|
      "#{s.date_and_time.strftime("%A, %B %d at %l:%M %p").strip} - #{s.display_name}"
    end.join("<br>")

    {
      role_name: @role.name,
      production_name: @production.name,
      claim_url: @claim_url,
      shows_list: shows_text
    }
  end

  def send_in_app_message(rendered)
    return unless @person.present? && @person.user.present?

    # Find a sender for the message (production team member)
    sender = find_sender

    MessageService.send_direct(
      sender: sender,
      recipient_person: @person,
      subject: rendered[:subject],
      body: rendered[:body],
      production: @production,
      organization: @production.organization
    )
  rescue => e
    Rails.logger.error("Failed to send vacancy invitation message: #{e.message}")
  end

  def find_sender
    # Try to find a team member to send from
    @production.production_permissions.includes(:user).first&.user ||
      @production.organization.organization_roles.includes(:user).first&.user
  end

  def find_email_batch_id
    @email_batch_id
  end
end

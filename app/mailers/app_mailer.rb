# frozen_string_literal: true

# Consolidated mailer for all application emails.
# Uses ContentTemplateService to render templates.
#
# This replaces all individual mailers with a single, unified mailer.
#
# Usage:
#   AppMailer.with(
#     template_key: "auth_welcome",
#     to: user.email_address,
#     variables: { user_email: user.email_address }
#   ).send_template.deliver_later
#
class AppMailer < ApplicationMailer
  # Generic template-based email sender
  def send_template
    @template_key = params[:template_key]
    @to = params[:to]
    @variables = params[:variables] || {}
    @email_batch_id = params[:email_batch_id]

    # Render the template
    rendered = ContentTemplateService.render(@template_key, @variables)
    @subject = rendered[:subject]
    @body = rendered[:body]

    headers["X-Email-Batch-ID"] = @email_batch_id.to_s if @email_batch_id.present?

    mail(to: @to, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end

  # Convenience class methods for common email types
  class << self
    # Auth emails
    def welcome(user)
      with(
        template_key: "auth_welcome",
        to: user.email_address,
        variables: { user_email: user.email_address }
      )
    end

    def password_reset(user, token)
      reset_url = Rails.application.routes.url_helpers.reset_url(token, host: default_url_host)
      with(
        template_key: "auth_password_reset",
        to: user.email_address,
        variables: { reset_url: reset_url }
      )
    end

    # Invitation emails
    def person_invitation(person_invitation, custom_message: nil)
      accept_url = Rails.application.routes.url_helpers.accept_invitation_url(
        person_invitation.token,
        host: default_url_host
      )
      org_name = person_invitation.organization&.name || "CocoScout"

      with(
        template_key: "person_invitation",
        to: person_invitation.email,
        variables: {
          organization_name: org_name,
          accept_url: accept_url,
          custom_message: custom_message
        }
      )
    end

    def group_invitation(group_invitation, custom_message: nil)
      accept_url = Rails.application.routes.url_helpers.accept_group_invitation_url(
        group_invitation.token,
        host: default_url_host
      )

      with(
        template_key: "group_invitation",
        to: group_invitation.email,
        variables: {
          group_name: group_invitation.group.name,
          invited_by_name: group_invitation.invited_by&.name || "Someone",
          accept_url: accept_url,
          custom_message: custom_message
        }
      )
    end

    def shoutout_notification(shoutout)
      shoutee = shoutout.shoutee
      # For email (no account), link to public profile shoutouts page
      shoutout_url = Rails.application.routes.url_helpers.public_profile_shoutouts_url(shoutee.public_key, host: default_url_host)

      with(
        template_key: "shoutout_notification",
        to: shoutee.email,
        variables: {
          author_name: shoutout.author.name,
          recipient_name: shoutee.first_name || "there",
          shoutout_message: shoutout.content,
          shoutout_url: shoutout_url
        }
      )
    end

    def team_organization_invitation(team_invitation, custom_message: nil)
      accept_url = Rails.application.routes.url_helpers.accept_team_invitation_url(
        team_invitation.token,
        host: default_url_host
      )

      with(
        template_key: "team_organization_invitation",
        to: team_invitation.email,
        variables: {
          organization_name: team_invitation.organization.name,
          accept_url: accept_url,
          custom_message: custom_message
        }
      )
    end

    def team_production_invitation(team_invitation, custom_message: nil)
      accept_url = Rails.application.routes.url_helpers.accept_team_invitation_url(
        team_invitation.token,
        host: default_url_host
      )

      with(
        template_key: "team_production_invitation",
        to: team_invitation.email,
        variables: {
          production_name: team_invitation.production.name,
          accept_url: accept_url,
          custom_message: custom_message
        }
      )
    end

    def vacancy_invitation(invitation, email_batch_id: nil)
      vacancy = invitation.role_vacancy
      show = vacancy.show

      with(
        template_key: "vacancy_invitation",
        to: invitation.person.email,
        email_batch_id: email_batch_id,
        variables: {
          recipient_name: invitation.person.name,
          production_name: show.production.name,
          role_name: vacancy.role.name,
          show_name: show.display_name,
          show_date: show.date_and_time.strftime("%B %-d, %Y at %l:%M %p"),
          claim_url: Rails.application.routes.url_helpers.claim_vacancy_url(invitation.token, host: default_url_host),
          custom_message: invitation.email_body
        }
      )
    end

    # Unread message digest
    def unread_digest(user, subject:, body:)
      with(
        template_key: "unread_message_digest",
        to: user.email_address,
        variables: {
          subject: subject,
          body: body
        }
      )
    end

    private

    def default_url_host
      Rails.application.config.action_mailer.default_url_options[:host] || "localhost:3000"
    end
  end
end

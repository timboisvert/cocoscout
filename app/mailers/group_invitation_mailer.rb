# frozen_string_literal: true

class GroupInvitationMailer < ApplicationMailer
  def invitation(group_invitation, subject = nil, message = nil)
    @invitation = group_invitation
    @token = group_invitation.token
    @group = group_invitation.group
    @custom_message = message
    @invited_by = group_invitation.invited_by

    accept_url = Rails.application.routes.url_helpers.accept_group_invitation_url(
      @token,
      host: ENV.fetch("HOST", "localhost:3000")
    )

    rendered = ContentTemplateService.render("group_invitation", {
      group_name: @group.name,
      inviter_name: @invited_by&.full_name || "A group member",
      accept_url: accept_url,
      custom_message: message
    })

    @subject = subject.presence || rendered[:subject]
    @body = rendered[:body]

    mail(to: @invitation.email, subject: @subject) do |format|
      format.html { render html: @body.html_safe }
    end
  end
end

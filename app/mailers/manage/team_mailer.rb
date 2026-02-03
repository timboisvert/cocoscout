# frozen_string_literal: true

module Manage
  class TeamMailer < ApplicationMailer
    def invite(team_invitation, subject = nil, message = nil)
      @team_invitation = team_invitation
      @custom_message = message

      accept_url = Rails.application.routes.url_helpers.accept_team_invitation_url(
        team_invitation.token,
        host: ENV.fetch("HOST", "localhost:3000")
      )

      rendered = ContentTemplateService.render("team_organization_invitation", {
        organization_name: team_invitation.organization.name,
        inviter_name: team_invitation.inviter&.full_name || "A team member",
        accept_url: accept_url,
        custom_message: message
      })

      @subject = subject.presence || rendered[:subject]
      @body = rendered[:body]

      mail(to: @team_invitation.email, subject: @subject) do |format|
        format.html { render html: @body.html_safe }
      end
    end

    def production_invite(team_invitation, subject = nil, message = nil)
      @team_invitation = team_invitation
      @production = team_invitation.production
      @organization = team_invitation.organization
      @custom_message = message

      accept_url = Rails.application.routes.url_helpers.accept_team_invitation_url(
        team_invitation.token,
        host: ENV.fetch("HOST", "localhost:3000")
      )

      rendered = ContentTemplateService.render("team_production_invitation", {
        production_name: @production.name,
        organization_name: @organization.name,
        inviter_name: team_invitation.inviter&.full_name || "A team member",
        accept_url: accept_url,
        custom_message: message
      })

      @subject = subject.presence || rendered[:subject]
      @body = rendered[:body]

      mail(to: @team_invitation.email, subject: @subject) do |format|
        format.html { render html: @body.html_safe }
      end
    end
  end
end

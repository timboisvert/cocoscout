# frozen_string_literal: true

module Manage
  class TeamMailer < ApplicationMailer
    def invite(team_invitation, subject = nil, message = nil)
      @team_invitation = team_invitation
      @custom_message = message

      accept_url = Rails.application.routes.url_helpers.accept_team_invitation_url(
        team_invitation.token,
        **default_url_options
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
        format.html { render html: @body.html_safe, layout: "mailer" }
      end
    end

    def production_invite(team_invitation, subject = nil, message = nil)
      @team_invitation = team_invitation
      @production = team_invitation.production
      @organization = team_invitation.organization
      @custom_message = message

      accept_url = Rails.application.routes.url_helpers.accept_manage_team_invitations_url(
        team_invitation.token,
        **default_url_options
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
        format.html { render html: @body.html_safe, layout: "mailer" }
      end
    end

    # Onto a contract (a contract person, ContractPeopleAdder), not a
    # production's team: they'll see the contract and its dates on My.
    def contract_invite(team_invitation, name: nil)
      @team_invitation = team_invitation
      contract = team_invitation.contract

      accept_url = Rails.application.routes.url_helpers.accept_manage_team_invitations_url(team_invitation.token, **default_url_options)

      rendered = ContentTemplateService.render("contract_person_invitation", {
        name: name,
        contractor_name: contract.contractor_name,
        organization_name: team_invitation.organization.name,
        production_name: contract.production_name.presence || contract.production&.name || "their production",
        accept_url: accept_url
      })

      mail(to: team_invitation.email, subject: rendered[:subject]) do |format|
        format.html { render html: rendered[:body].html_safe, layout: "mailer" }
      end
    end
  end
end

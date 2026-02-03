# frozen_string_literal: true

module Manage
  class PersonMailer < ApplicationMailer
    def person_invitation(person_invitation, subject = nil, message = nil, email_batch_id: nil)
      @person_invitation = person_invitation
      @token = person_invitation.token
      @organization = person_invitation.organization
      @custom_message = message
      @email_batch_id = email_batch_id

      accept_url = Rails.application.routes.url_helpers.manage_accept_person_invitations_url(
        @token,
        host: ENV.fetch("HOST", "localhost:3000")
      )
      org_name = @organization&.name || "CocoScout"

      rendered = ContentTemplateService.render("person_invitation", {
        organization_name: org_name,
        accept_url: accept_url,
        custom_message: message
      })

      @subject = subject.presence || rendered[:subject]
      @body = rendered[:body]

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: @person_invitation.email, subject: @subject) do |format|
        format.html { render html: @body.html_safe }
      end
    end

    private

    def find_email_batch_id
      @email_batch_id
    end

    def find_production_id
      @production_id || super
    end
  end
end

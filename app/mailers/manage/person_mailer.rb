# frozen_string_literal: true

module Manage
  class PersonMailer < ApplicationMailer
    def person_invitation(person_invitation, subject: nil, body: nil, email_batch_id: nil)
      @person_invitation = person_invitation
      @token = person_invitation.token
      @organization = person_invitation.organization
      @email_batch_id = email_batch_id

      setup_url = Rails.application.routes.url_helpers.manage_accept_person_invitations_url(
        @token,
        host: ENV.fetch("HOST", "localhost:3000")
      )
      org_name = @organization&.name || "CocoScout"

      # If subject/body provided, interpolate the setup_url variable
      # Otherwise fall back to template defaults
      if subject.present? && body.present?
        @subject = subject.gsub("{{setup_url}}", setup_url).gsub("{{organization_name}}", org_name)
        @body = body.gsub("{{setup_url}}", setup_url).gsub("{{organization_name}}", org_name)
      else
        rendered = ContentTemplateService.render("person_invitation", {
          organization_name: org_name,
          setup_url: setup_url
        })
        @subject = rendered[:subject]
        @body = rendered[:body]
      end

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: @person_invitation.email, subject: @subject) do |format|
        format.html { render html: @body.html_safe, layout: "mailer" }
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

# frozen_string_literal: true

module Manage
  class PersonMailer < ApplicationMailer
    def person_invitation(person_invitation, subject = nil, message = nil, email_batch_id: nil)
      @person_invitation = person_invitation
      @token = person_invitation.token
      @organization = person_invitation.organization
      @custom_message = message
      @email_batch_id = email_batch_id

      subject ||= if @organization
                    "You've been invited to join #{@organization.name} on CocoScout"
      else
                    "You've been invited to join CocoScout"
      end

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: @person_invitation.email, subject: subject)
    end

    def contact_email(person, subject, message, sender, production_id: nil, organization_id: nil)
      @person = person
      @subject = subject
      @message = message
      @sender = sender
      @production_id = production_id
      @production = Production.find_by(id: production_id) if production_id
      @organization = Organization.find_by(id: organization_id) if organization_id
      mail(to: person.email, subject: subject)
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

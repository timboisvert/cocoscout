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

    private

    def find_email_batch_id
      @email_batch_id
    end

    def find_production_id
      @production_id || super
    end
  end
end

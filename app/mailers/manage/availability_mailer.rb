# frozen_string_literal: true

module Manage
  class AvailabilityMailer < ApplicationMailer
    def request_availability(person, production, message, email_batch_id: nil)
      @person = person
      @production = production
      @message = message
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: person.email, subject: "Please submit your availability for #{production.name}")
    end

    def request_availability_for_group(group, production, message, email_batch_id: nil)
      @group = group
      @production = production
      @message = message
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: group.email, subject: "Please submit availability for #{group.name} - #{production.name}")
    end

    private

    def find_email_batch_id
      @email_batch_id
    end
  end
end

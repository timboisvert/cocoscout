# frozen_string_literal: true

module Manage
  class QuestionnaireMailer < ApplicationMailer
    def invitation(person, questionnaire, production, subject, message, email_batch_id: nil)
      @person = person
      @questionnaire = questionnaire
      @production = production
      @message = message
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(
        to: person.user.email_address,
        subject: subject
      )
    end

    private

    def find_email_batch_id
      @email_batch_id
    end
  end
end

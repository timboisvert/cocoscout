# frozen_string_literal: true

class CourseQuestionnaireDeliveryJob < ApplicationJob
  queue_as :default

  def perform(course_registration_id)
    registration = CourseRegistration.find_by(id: course_registration_id)
    return unless registration&.confirmed?

    offering = registration.course_offering
    questionnaire = offering.questionnaire
    return unless questionnaire&.accepting_responses

    person = registration.person
    return unless person

    # Idempotent: skip if invitation already exists for this context
    return if questionnaire.questionnaire_invitations.exists?(invitee: person, context: offering)

    # Create invitation with course offering context
    QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person, context: offering)

    # Send in-app message if person has a user account
    return unless person.user

    organization = offering.production.organization
    questionnaire_url = Rails.application.routes.url_helpers.my_questionnaire_form_url(
      token: questionnaire.token,
      ctx: "CourseOffering-#{offering.id}",
      **Rails.application.config.action_mailer.default_url_options
    )

    # Use the offering's saved email draft if present, otherwise fall back to content template
    draft = offering.email_draft
    if draft&.title.present? && draft&.body.present?
      subject = draft.title
      body = draft.body.to_s.gsub("{{questionnaire_url}}", questionnaire_url)
                              .gsub("{{person_name}}", person.first_name || "there")
                              .gsub("{{questionnaire_title}}", questionnaire.title)
    else
      rendered = ContentTemplateService.render("questionnaire_invitation", {
        person_name: person.first_name || "there",
        questionnaire_title: questionnaire.title,
        questionnaire_url: questionnaire_url
      })
      subject = rendered[:subject]
      body = rendered[:body]
    end

    MessageService.send_direct(
      sender: nil,
      recipient_person: person,
      subject: subject,
      body: body,
      organization: organization
    )
  end
end

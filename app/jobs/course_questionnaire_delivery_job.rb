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

    # Idempotent: skip if invitation already exists
    return if questionnaire.questionnaire_invitations.exists?(invitee: person)

    # Create invitation
    QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person)

    # Send in-app message if person has a user account
    return unless person.user

    production = offering.production
    questionnaire_url = Rails.application.routes.url_helpers.my_questionnaire_url(
      questionnaire,
      host: ENV.fetch("HOST", "localhost:3000")
    )

    rendered = ContentTemplateService.render("questionnaire_invitation", {
      person_name: person.first_name || "there",
      questionnaire_title: questionnaire.title,
      production_name: production.name,
      questionnaire_url: questionnaire_url,
      custom_message: ""
    })

    MessageService.send_direct(
      sender: nil,
      recipient_person: person,
      subject: rendered[:subject],
      body: rendered[:body],
      production: production,
      organization: production.organization
    )
  end
end

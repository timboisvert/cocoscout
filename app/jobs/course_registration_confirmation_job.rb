# frozen_string_literal: true

class CourseRegistrationConfirmationJob < ApplicationJob
  queue_as :default

  def perform(course_registration_id)
    registration = CourseRegistration.find_by(id: course_registration_id)
    return unless registration
    return unless registration.confirmed?

    offering = registration.course_offering
    production = offering.production
    person = registration.person
    org = production.organization

    # Add person to the production's talent pool so they see course sessions
    # in their dashboard and My Shows
    talent_pool = production.talent_pool
    unless talent_pool.talent_pool_memberships.exists?(member: person)
      talent_pool.talent_pool_memberships.create!(member: person)
    end

    # Ensure the person is associated with the organization
    unless org.people.include?(person)
      org.people << person
    end

    # Send confirmation email + in-app message to registrant
    CourseRegistrationNotificationService.notify_registrant(registration)

    # Send in-app message to production team
    CourseRegistrationNotificationService.notify_team(registration)

    # Deliver course questionnaire if configured
    deliver_questionnaire(registration, offering)
  end

  private

  def deliver_questionnaire(registration, offering)
    return unless offering.questionnaire_id.present?

    case offering.delivery_mode
    when "immediate"
      CourseQuestionnaireDeliveryJob.perform_later(registration.id)
    when "delayed"
      delay = (offering.delivery_delay_minutes || 0).minutes
      CourseQuestionnaireDeliveryJob.set(wait: delay).perform_later(registration.id)
    when "scheduled"
      if offering.delivery_scheduled_at.present? && offering.delivery_scheduled_at > Time.current
        CourseQuestionnaireDeliveryJob.set(wait_until: offering.delivery_scheduled_at).perform_later(registration.id)
      else
        # Scheduled time has passed — deliver immediately
        CourseQuestionnaireDeliveryJob.perform_later(registration.id)
      end
    # "manual" mode: do nothing — producer triggers bulk send from course page
    end
  end
end

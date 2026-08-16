# frozen_string_literal: true

# Carries out a course cancellation after the manager confirms it: refunds
# every paid registrant through Stripe, removes anyone still pending, cancels
# the class sessions, and tells the people affected. The payout dissolves on its
# own as each refund lands (CourseRegistration resyncs it).
#
# Runs off the request thread because it talks to Stripe once per registrant.
# Idempotent and re-runnable: a registrant already refunded is skipped, so a
# retry after a Stripe hiccup only touches what's still outstanding. A refund
# that fails leaves its registration confirmed — visible on the course page,
# never silently lost.
class CourseCancellationJob < ApplicationJob
  queue_as :default

  TEMPLATE_KEY = "course_cancelled_registrant"

  def perform(course_offering_id)
    offering = CourseOffering.find_by(id: course_offering_id)
    return unless offering&.cancelled?

    affected = []

    offering.course_registrations.confirmed.includes(:person).find_each do |registration|
      result = CourseRegistrationRefundService.call(registration)
      if result.ok?
        affected << registration
      else
        Rails.logger.warn "[CourseCancellationJob] Refund failed for registration #{registration.id}: #{result.error}"
      end
    end

    offering.course_registrations.pending.includes(:person).find_each do |registration|
      registration.cancel!
      affected << registration
    end

    cancel_sessions(offering)
    notify(offering, affected) if offering.cancellation_notify_registrants? && affected.any?
  end

  private

  # The class sessions themselves — nothing to turn up for now.
  def cancel_sessions(offering)
    offering.sessions.where(canceled: false).find_each { |show| show.update!(canceled: true) }
  end

  def notify(offering, registrations)
    production = offering.production
    sender = production.organization.owner ||
             production.production_permissions.includes(:user).find_by(role: "manager")&.user
    return unless sender

    by_person = registrations.index_by(&:person)
    NotificationDeliveryService.deliver_to_many(
      template_key: TEMPLATE_KEY,
      variables_proc: lambda { |person|
        registration = by_person[person]
        {
          recipient_name: person.first_name.presence || person.name&.split&.first || "there",
          course_title: offering.title,
          organization_name: production.organization.name,
          refund_amount: registration.refunded? && registration.amount_cents.to_i.positive? ? registration.formatted_amount : nil
        }
      },
      sender: sender,
      recipients: by_person.keys,
      production: production,
      organization: production.organization,
      system_generated: true
    )
  end
end

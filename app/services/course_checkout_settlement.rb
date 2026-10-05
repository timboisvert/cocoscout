# frozen_string_literal: true

# A paid (or free) course registration becomes confirmed: once, whichever
# arrives first of the done page and the payment_intent.succeeded webhook.
# A payment that lands after the hold lapsed still counts while the spot is
# there; if the course filled meanwhile, the money goes straight back.
class CourseCheckoutSettlement
  class Error < StandardError; end

  def self.settle!(registration, payment_intent_id: nil, charge_id: nil)
    registration.with_lock do
      return registration if registration.confirmed?
      raise Error, "This registration can't be paid (#{registration.status})." unless registration.pending? || registration.expired?

      offering = registration.course_offering
      if (registration.expired? || registration.hold_expired?) && offering.capacity.present? &&
         offering.confirmed_registrations_count >= offering.capacity
        return refund_late_payment!(registration, payment_intent_id)
      end

      begin
        registration.update!(status: "confirmed", paid_at: Time.current, expires_at: nil,
                             stripe_payment_intent_id: payment_intent_id || registration.stripe_payment_intent_id,
                             stripe_charge_id: charge_id || registration.stripe_charge_id)
      rescue ActiveRecord::RecordNotUnique
        # They got confirmed another way while this payment was in flight.
        return refund_late_payment!(registration, payment_intent_id)
      end
      CourseTax.record!(registration)
      registration.record_stripe_fee!
      CourseRegistrationConfirmationJob.perform_later(registration.id)
    end
    registration
  end

  def self.refund_late_payment!(registration, payment_intent_id)
    intent_id = payment_intent_id || registration.stripe_payment_intent_id
    Stripe::Refund.create({ payment_intent: intent_id }, { idempotency_key: "course-late-refund-#{registration.id}" }) if intent_id
    registration.update!(status: "refunded", refunded_at: Time.current, expires_at: nil, stripe_payment_intent_id: intent_id)
    Rails.logger.warn("[CourseCheckoutSettlement] registration #{registration.id} paid after the course filled; refunded")
    registration
  end
  private_class_method :refund_late_payment!
end

# frozen_string_literal: true

# Registering for a course, the way tickets are bought: a pending
# registration holds the spot for ten minutes while the student pays on our
# own page (My::CourseCheckoutsController), then CourseCheckoutSettlement
# confirms it. Students keep an account, so the hold belongs to a person.
class CourseCheckout
  class Error < StandardError; end

  HOLD = CourseRegistration::HOLD

  # One live hold per person and course: coming back reuses it (repriced if
  # the early-bird deadline passed meanwhile).
  def self.start!(offering:, user:)
    person = user&.person
    raise Error, "Finish setting up your profile first." unless person
    raise Error, "You're already registered for this course." if offering.course_registrations.confirmed.exists?(person: person)

    offering.with_lock do
      held = offering.course_registrations.holding.find_by(person: person)
      return reprice!(held) if held

      raise Error, offering.registration_closed_reason unless offering.accepting_registrations?

      quote = CourseTax.quote(offering)
      offering.course_registrations.create!(
        person: person, user: user, status: "pending", registered_at: Time.current, expires_at: HOLD.from_now,
        amount_cents: quote.base_cents, tax_cents: quote.tax_cents, currency: offering.currency.presence || "usd",
        cocoscout_fee_cents: CourseRegistration.platform_fee_cents_for(offering, quote.base_cents)
      )
    end
  end

  def self.reprice!(registration)
    quote = CourseTax.quote(registration.course_offering)
    if registration.amount_cents != quote.base_cents || registration.tax_cents != quote.tax_cents
      registration.update!(amount_cents: quote.base_cents, tax_cents: quote.tax_cents,
                           cocoscout_fee_cents: CourseRegistration.platform_fee_cents_for(registration.course_offering, quote.base_cents))
    end
    registration
  end
end

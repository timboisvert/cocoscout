# frozen_string_literal: true

# Adding a student to a course by hand: a walk-in who paid cash, a friend of
# the instructor, someone moved from a waitlist. They get a confirmed
# registration like anyone else (and the confirmation email, unless the
# manager says not to), take a spot, and join the production's talent pool.
# No CocoScout fee: the money, if any, never touched CocoScout.
class CourseStudents
  class Error < StandardError; end

  PAID_VIA = %w[free cash check zelle venmo other].freeze
  PAID_WORDS = { "free" => "Free", "cash" => "Cash", "check" => "Check", "zelle" => "Zelle", "venmo" => "Venmo", "other" => "Paid another way" }.freeze

  def self.add!(offering:, name:, email:, paid_via:, by:, email_them: true)
    name = name.to_s.squish
    email = email.to_s.strip.downcase
    raise Error, "Give the student a name and an email." if name.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
    raise Error, "Pick how they paid." unless PAID_VIA.include?(paid_via.to_s)
    raise Error, offering.registration_closed_reason if offering.full?

    person = find_or_create_person(offering, name, email)
    raise Error, "#{person.name} is already registered." if offering.course_registrations.confirmed.exists?(person: person)

    quote = CourseTax.quote(offering)
    free = paid_via == "free"
    registration = offering.course_registrations.create!(
      person: person, user: person.user, status: "confirmed", channel: "manual", paid_via: paid_via, added_by: by,
      registered_at: Time.current, paid_at: Time.current,
      amount_cents: free ? 0 : quote.base_cents, tax_cents: free ? 0 : quote.tax_cents, cocoscout_fee_cents: 0,
      currency: offering.currency.presence || "usd"
    )
    CourseTax.record!(registration)
    CourseRegistrationConfirmationJob.perform_later(registration.id, email_student: email_them)
    registration
  rescue ActiveRecord::RecordNotUnique
    raise Error, "#{name} is already registered."
  end

  # The theater's own person by that email first, then anyone on CocoScout,
  # else a new person (who can claim an account later).
  def self.find_or_create_person(offering, name, email)
    organization = offering.production.organization
    organization.people.find_by(email: email) || Person.where(email: email).order(:id).first || Person.create!(name: name, email: email)
  end
end

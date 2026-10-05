# frozen_string_literal: true

require "rails_helper"

# After paying: the receipt page (every session, what they paid, the calendar
# file, the email again) and the emails a student gets: the confirmation
# with the when-and-where block and the receipt, a refund, being taken off.
RSpec.describe "Course receipt and emails", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let(:location) { create(:location, organization: org, name: "The Annex", address1: "1 Main St", city: "Chicago", state: "IL") }
  let!(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000, capacity: 12) }
  let!(:sessions) do
    [ 3, 10 ].map { |day| create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, day, 19, 0), duration_minutes: 120, location: location) }
  end
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: "fox@example.com", name: "Fox Mulder") }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "8", mode: "added")
    TicketingProfile.for(org).update!(support_email: "classes@starsandgarters.com")
    allow(Stripe::Refund).to receive(:create).and_return(Stripe::Refund.construct_from(id: "re_1"))
  end

  def registered
    registration = CourseCheckout.start!(offering: offering, user: user)
    allow(registration).to receive(:record_stripe_fee!)
    CourseCheckoutSettlement.settle!(registration, payment_intent_id: "pi_1", charge_id: "ch_1")
    registration.reload
  end

  it "shows the receipt, gives a calendar file with every session, and emails it again" do
    registration = registered
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get my_course_success_path(code: offering.short_code, token: registration.token)
    expect(response.body).to include("You&#39;re registered", "Starts Tuesday, November 3 · 7:00 – 9:00 PM", "2 sessions", "The Annex",
                                     "Tue, Nov 10", "What you paid", "Course fee", "$100.00", "Sales tax 8%", "$8.00", "$108.00",
                                     "Add to calendar", "Directions", "Email this again")

    get my_course_calendar_path(code: offering.short_code, token: registration.token)
    expect(response.media_type).to eq("text/calendar")
    expect(response.body.scan("BEGIN:VEVENT").size).to eq(2)
    expect(response.body).to include("SUMMARY:Improv 101", "DTSTART:202611")

    expect { post my_course_resend_path(code: offering.short_code, token: registration.token) }
      .to have_enqueued_mail(CourseRegistrationMailer, :confirmation)
    expect(response).to redirect_to(my_course_success_path(code: offering.short_code, token: registration.token))
  end

  it "keeps the receipt to its own person" do
    registration = registered
    other = create(:user, password: password)
    create(:person, user: other, email: other.email_address)
    post handle_signin_path, params: { email_address: other.email_address, password: password }
    get my_course_success_path(code: offering.short_code, token: registration.token)
    expect(response).to redirect_to(my_course_show_path(code: offering.short_code))
    get my_course_calendar_path(code: offering.short_code, token: registration.token)
    expect(response).to have_http_status(:not_found)
  end

  it "confirms with the when-and-where block, every session, the receipt and where questions go, from the theater" do
    registration = registered
    perform_enqueued_jobs(only: CourseRegistrationConfirmationJob)
    mail = CourseRegistrationMailer.confirmation(registration)
    expect(mail.to).to eq([ "fox@example.com" ])
    expect(mail.subject).to eq("You're registered for Improv 101")
    expect(mail[:from].display_names).to eq([ "Stars & Garters via CocoScout" ])
    expect(mail.reply_to).to eq([ "classes@starsandgarters.com" ])
    html = mail.html_part.body.to_s
    expect(html).to include("Hi Fox,", "2 sessions starting Tuesday, November 3 at 7:00 PM", ">When<", "Tuesday, November 3", ">Where<", "The Annex",
                            "Add to calendar", "Every session", "Tue, Nov 10", "What you paid", "$108.00", "Questions about the course?", "classes@starsandgarters.com")
    # The in-app note carries the same words.
    expect(Message.last&.subject).to eq("You're registered for Improv 101")
  end

  it "tells the student about a refund, and about being taken off, but not twice when the whole course is canceled" do
    registration = registered
    expect { CourseRegistrationRefundService.call(registration) }.to have_enqueued_mail(CourseRegistrationMailer, :refunded)
    mail = CourseRegistrationMailer.refunded(registration.reload)
    expect(mail.html_part.body.to_s).to include("refunded your registration", "$108.00", "Questions about the course?")

    second = create(:user, password: password)
    create(:person, user: second, email: "dana@example.com", name: "Dana Scully")
    other = CourseCheckout.start!(offering: offering, user: second)
    allow(other).to receive(:record_stripe_fee!)
    CourseCheckoutSettlement.settle!(other, payment_intent_id: "pi_2")
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
    expect { post manage_course_offering_cancel_registration_path(offering, registration_id: other.id) }
      .to have_enqueued_mail(CourseRegistrationMailer, :removed)
    expect(other.reload).to be_cancelled

    third = create(:user, password: password)
    create(:person, user: third, email: "walter@example.com", name: "Walter Skinner")
    kept = CourseCheckout.start!(offering: offering, user: third)
    CourseCheckoutSettlement.settle!(kept, payment_intent_id: "pi_3")
    offering.update!(status: "cancelled", cancellation_notify_registrants: true)
    expect { CourseCancellationJob.perform_now(offering.id) }.not_to have_enqueued_mail(CourseRegistrationMailer, :refunded)
    expect(kept.reload).to be_refunded
  end
end

# frozen_string_literal: true

require "rails_helper"

# The manager's side of a course: a student added by hand (free, or paid
# another way), the tiles, and sending the confirmation again.
RSpec.describe "Course students (manage)", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000, capacity: 3) }
  let!(:session_show) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 10, 19, 0)) }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "8", mode: "added")
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "adds a student who paid cash, then one for free, and counts them like anyone else" do
    get manage_course_offering_path(offering)
    expect(response.body).to include("Add a student", ">Registered<", "0 of 3")

    post manage_course_offering_students_path(offering), params: { name: "Dana Scully", email: "Dana@Example.com", paid_via: "cash", email_them: "1" }
    expect(response).to redirect_to(manage_new_course_offering_student_path(offering, paid_via: "cash"))
    expect(flash[:notice]).to eq("Dana Scully is registered, cash. Add the next one, or go back.")
    dana = offering.course_registrations.confirmed.sole
    expect(dana.person.email).to eq("dana@example.com")
    expect(dana.person.user).to be_nil
    expect(dana.channel).to eq("manual")
    expect(dana.amount_cents).to eq(10_000)
    expect(dana.tax_cents).to eq(800)
    expect(dana.cocoscout_fee_cents).to eq(0)
    expect(dana.added_by).to eq(owner)
    expect(dana.tax_lines.sum(:tax_cents)).to eq(800)
    expect(OrgCashEntry.where(source: dana)).to be_empty
    expect { perform_enqueued_jobs(only: CourseRegistrationConfirmationJob) }.to have_enqueued_mail(CourseRegistrationMailer, :confirmation)
    expect(production.talent_pool.talent_pool_memberships.exists?(member: dana.person)).to be(true)

    existing = create(:person, user: create(:user), email: "fox@example.com", name: "Fox Mulder")
    post manage_course_offering_students_path(offering), params: { name: "F. Mulder", email: "fox@example.com", paid_via: "free", email_them: "0" }
    fox = offering.course_registrations.confirmed.find_by(person: existing)
    expect(fox.amount_cents).to eq(0)
    expect(fox.paid_via).to eq("free")
    expect { perform_enqueued_jobs(only: CourseRegistrationConfirmationJob) }.not_to have_enqueued_mail(CourseRegistrationMailer, :confirmation)

    get manage_course_offering_path(offering)
    expect(response.body).to include("2 of 3", "2 students added by hand", "$100.00", "Registered Oct 4, 2026 · Cash", "· Free")

    post manage_course_offering_students_path(offering), params: { name: "Dana Scully", email: "dana@example.com", paid_via: "cash" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Dana Scully is already registered.")
  end

  it "won't add past capacity, and sends the confirmation again on request" do
    3.times { |i| CourseStudents.add!(offering: offering, name: "Student #{i}", email: "s#{i}@example.com", paid_via: "cash", by: owner) }
    post manage_course_offering_students_path(offering), params: { name: "One More", email: "more@example.com", paid_via: "cash" }
    expect(response.body).to include("This course is full")

    registration = offering.course_registrations.confirmed.first
    expect { post manage_course_offering_resend_confirmation_path(offering, registration) }.to have_enqueued_mail(CourseRegistrationMailer, :confirmation).with(registration)
    expect(flash[:notice]).to include("their confirmation again")

    CourseRegistrationRefundService.call(registration)
    mail = CourseRegistrationMailer.refunded(registration.reload)
    expect(mail.html_part.body.to_s).to include("$108.00. Your spot is released")
    expect(mail.html_part.body.to_s).not_to include("card you paid with")
  end
end

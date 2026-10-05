# frozen_string_literal: true

require "rails_helper"

# The manager's side: the course page asks when a session moved, the review
# page sends in their words; canceling a class session in Shows & Events
# offers to email the students; the reminder setting lives in Course settings.
RSpec.describe "Course session notices (manage)", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let(:location) { create(:location, organization: org, name: "The Annex") }
  let(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000) }
  let!(:session_show) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 10, 19, 0), location: location) }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    user = create(:user)
    create(:person, user: user, email: "dana@example.com", name: "Dana Scully")
    CourseCheckoutSettlement.settle!(CourseCheckout.start!(offering: offering, user: user))
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "asks on the course page once a session moved, then emails the students in the manager's words" do
    get manage_course_offering_path(offering)
    expect(response.body).not_to include("Tell students about the change")

    session_show.update!(date_and_time: Time.zone.local(2026, 11, 11, 19, 0))
    get manage_course_offering_path(offering)
    expect(response.body).to include("Tell students about the change")

    get manage_course_offering_change_path(offering)
    expect(response.body).to include("1 student registered before it changed", "Dana Scully", "How it reads for Dana Scully", "Wednesday, November 11")

    post manage_course_offering_change_path(offering), params: { subject: "New date for {{course_title}}", body: "Hi {{first_name}}, it's now {{now}}." }
    expect(response).to redirect_to(manage_course_offering_path(offering))
    expect { perform_enqueued_jobs(only: CourseSessionChangeJob) }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.subject).to eq("New date for Improv 101")
    get manage_course_offering_change_path(offering)
    expect(response).to redirect_to(manage_course_offering_path(offering))
  end

  it "offers to email the students when a class session is canceled, and does" do
    get manage_cancel_show_form_path(production, session_show)
    expect(response.body).to include("Email the students", "1 student", "{{sessions}}", "Dana Scully")

    patch manage_cancel_show_path(production, session_show),
          params: { scope: "this", notify_cast: "0", email_students: "1", course_email_subject: "{{course_title}}: {{sessions}} canceled", course_email_body: "Sorry, {{first_name}}." }
    expect(flash[:notice]).to include("Emailing 1 student")
    expect(session_show.reload.canceled).to be(true)
    expect { perform_enqueued_jobs(only: CourseSessionCancellationJob) }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.subject).to eq("Improv 101: the Tuesday, November 10 session canceled")
  end

  it "sets how many days before a session the reminder goes" do
    get manage_course_settings_section_path(section: "reminders")
    expect(response.body).to include("Reminder email", "1 day before each session")
    patch manage_course_settings_reminders_path, params: { course_reminder_days_before: "3" }
    expect(org.reload.course_reminder_days_before).to eq(3)
    patch manage_course_settings_reminders_path, params: { course_reminder_days_before: "" }
    expect(org.reload.course_reminder_days_before).to be_nil
  end
end

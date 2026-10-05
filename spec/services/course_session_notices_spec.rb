# frozen_string_literal: true

require "rails_helper"

# Students hear about their sessions: one that moved (asked, read, sent),
# ones that were canceled, and the reminder before each.
RSpec.describe "Course session notices" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, name: "Stars & Garters", course_reminder_days_before: 1) }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let(:location) { create(:location, organization: org, name: "The Annex") }
  let(:annex_b) { create(:location, organization: org, name: "Annex B") }
  let(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000) }
  let!(:first) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 3, 19, 0), location: location) }
  let!(:second) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 10, 19, 0), location: location) }

  before { travel_to Time.zone.local(2026, 10, 4, 12, 0) }

  def student(name)
    user = create(:user)
    create(:person, user: user, email: "#{name.parameterize}@example.com", name: name)
    registration = CourseCheckout.start!(offering: offering, user: user)
    CourseCheckoutSettlement.settle!(registration)
    registration.reload
  end

  it "remembers what a student was told, notices a session that moved, and settles it by email or by hand" do
    dana = student("Dana Scully")
    expect(dana.told_sessions.keys).to contain_exactly(first.id.to_s, second.id.to_s)
    expect(CourseSessionChange.pending?(offering)).to be(false)

    second.update!(date_and_time: Time.zone.local(2026, 11, 11, 19, 30), location: annex_b)
    expect(CourseSessionChange.pending?(offering)).to be(true)
    moved = CourseSessionChange.moved(dana).sole
    vars = CourseSessionChange.variables(dana, moved)
    expect(vars[:what_changed]).to eq("date, time, and place")
    expect(vars[:was]).to eq("Tuesday, November 10 at 7:00 PM, at The Annex")
    expect(vars[:now]).to eq("Wednesday, November 11 at 7:30 PM, at Annex B")

    # Someone registering after the change was told the new time: nothing to say to them.
    fox = student("Fox Mulder")
    expect(CourseSessionChange.registrations(offering)).to eq([ dana ])

    draft = CourseSessionChange.draft(offering)
    expect(draft.subject).to include("{{what_changed}}")
    expect { CourseSessionChangeJob.perform_now(offering.id, draft.subject, draft.body) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "dana-scully@example.com" ])
    expect(mail.subject).to eq("Improv 101: a session has a new date, time, and place")
    expect(mail.html_part.body.to_s).to include("It was Tuesday, November 10 at 7:00 PM, at The Annex", "Wednesday, November 11", "Annex B", ">When<")
    expect(CourseSessionChange.pending?(offering)).to be(false)

    second.update!(date_and_time: Time.zone.local(2026, 11, 11, 20, 0))
    expect(CourseSessionChange.registrations(offering)).to contain_exactly(dana, fox)
    expect(CourseSessionChange.mark_told!(offering)).to eq(2)
    expect(CourseSessionChange.pending?(offering)).to be(false)
  end

  it "tells every student which sessions were canceled, in the manager's words" do
    student("Dana Scully")
    student("Fox Mulder")
    subject, body = CourseSessionCancellation.default_email
    expect(CourseSessionCancellation.start!([ second ], subject: subject, body: body)).to eq(2)
    expect { perform_enqueued_jobs(only: CourseSessionCancellationJob) }.to change { ActionMailer::Base.deliveries.size }.by(2)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to eq("Improv 101: the Tuesday, November 10 session canceled")
    expect(mail.html_part.body.to_s).to include("canceled the Tuesday, November 10 session", "Questions about the course?")
  end

  it "reminds each student once per session, the theater's number of days before" do
    dana = student("Dana Scully")
    expect { CourseRemindersJob.perform_now(Date.new(2026, 11, 2)) }.to have_enqueued_mail(CourseRegistrationMailer, :reminder).with(dana, first)
    expect(dana.reload.reminded_show_ids).to eq([ first.id ])
    expect { CourseRemindersJob.perform_now(Date.new(2026, 11, 2)) }.not_to have_enqueued_mail(CourseRegistrationMailer, :reminder)
    expect { CourseRemindersJob.perform_now(Date.new(2026, 11, 9)) }.to have_enqueued_mail(CourseRegistrationMailer, :reminder).with(dana, second)

    mail = CourseRegistrationMailer.reminder(dana, second)
    expect(mail.subject).to eq("Reminder: Improv 101 is on Tuesday, November 10")
    expect(mail.html_part.body.to_s).to include("See you on Tuesday, November 10!", "Tuesday, November 10", "The Annex")

    org.update!(course_reminder_days_before: nil)
    expect { CourseRemindersJob.perform_now(Date.new(2026, 11, 9)) }.not_to have_enqueued_mail(CourseRegistrationMailer, :reminder)
  end
end

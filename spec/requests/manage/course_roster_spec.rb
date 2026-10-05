# frozen_string_literal: true

require "rails_helper"

# The roster (printed, and as a CSV) and attendance per session.
RSpec.describe "Course roster and attendance (manage)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000) }
  let!(:sessions) { [ 3, 10 ].map { |d| create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, d, 19, 0)) } }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    CourseStudents.add!(offering: offering, name: "Dana Scully", email: "dana@example.com", paid_via: "cash", by: owner)
    CourseStudents.add!(offering: offering, name: "Fox Mulder", email: "fox@example.com", paid_via: "free", by: owner)
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "prints the roster with a box per session, and downloads it as a CSV" do
    get manage_course_offering_roster_path(offering)
    expect(response.body).to include("<title>Roster · Improv 101</title>", "2 students", "Dana Scully", "dana@example.com", ">Cash<", ">Free<", ">Nov 3<", ">Nov 10<")

    get manage_course_offering_roster_path(offering, format: :csv)
    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows.first).to eq([ "Name", "Email", "Registered", "Paid", "Nov 3", "Nov 10", "Attended" ])
    expect(rows.find { |r| r[0] == "Dana Scully" }).to eq([ "Dana Scully", "dana@example.com", "2026-10-04", "Cash", "", "", "0 of 2" ])
  end

  it "saves who came to each session" do
    dana = offering.course_registrations.confirmed.find_by(person: Person.find_by(email: "dana@example.com"))
    fox = offering.course_registrations.confirmed.find_by(person: Person.find_by(email: "fox@example.com"))
    get manage_course_offering_attendance_path(offering)
    expect(response.body).to include("Dana Scully", "Tue Nov 3", "Tue Nov 10", "0 of 2", "Save attendance")

    patch manage_course_offering_attendance_path(offering), params: { attended: { dana.id => [ "", sessions.first.id, sessions.last.id ], fox.id => [ "", sessions.first.id ] } }
    expect(response).to redirect_to(manage_course_offering_attendance_path(offering))
    expect(dana.reload.attended_show_ids).to contain_exactly(sessions.first.id, sessions.last.id)
    expect(fox.reload.attended_show_ids).to eq([ sessions.first.id ])

    patch manage_course_offering_attendance_path(offering), params: { attended: { dana.id => [ "" ], fox.id => [ "", sessions.first.id ] } }
    expect(dana.reload.attended_show_ids).to eq([])
    get manage_course_offering_roster_path(offering, format: :csv)
    expect(CSV.parse(response.body).find { |r| r[0] == "Fox Mulder" }.last(3)).to eq([ "Y", "", "1 of 2" ])
  end
end

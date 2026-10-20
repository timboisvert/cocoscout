# frozen_string_literal: true

require "rails_helper"

# Course attendance on a phone (V1.1 plan §4): one session at a time, and
# saving it leaves every other session alone.
RSpec.describe "Course attendance, one session at a time", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, owner: owner) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production) }
  let!(:first_session) { create(:show, production: production, course_offering_id: offering.id, event_type: "class", date_and_time: 2.days.ago.change(hour: 19)) }
  let!(:second_session) { create(:show, production: production, course_offering_id: offering.id, event_type: "class", date_and_time: 5.days.from_now.change(hour: 19)) }
  let!(:registration) { create(:course_registration, course_offering: offering, person: create(:person, name: "Fox Mulder")) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "shows one session's checklist on a phone, the next one by default" do
    get manage_course_offering_attendance_path(offering)
    checklist = Nokogiri::HTML(response.body).at_css("[data-course-session-checklist]")
    expect(checklist["class"]).to include("sm:hidden")
    expect(checklist.at_css("input[name='session_id']")["value"]).to eq(second_session.id.to_s)
    expect(checklist.text).to include("Fox Mulder", "0 of 1 here")
  end

  it "saves one session without touching the others" do
    registration.update_columns(attended_show_ids: [ second_session.id ])

    patch manage_course_offering_attendance_path(offering), params: { session_id: first_session.id, present: [ registration.id ] }
    expect(response).to redirect_to(manage_course_offering_attendance_path(offering, session_id: first_session.id))
    expect(registration.reload.attended_show_ids).to contain_exactly(first_session.id, second_session.id)

    patch manage_course_offering_attendance_path(offering), params: { session_id: first_session.id }
    expect(registration.reload.attended_show_ids).to eq([ second_session.id ])
  end
end

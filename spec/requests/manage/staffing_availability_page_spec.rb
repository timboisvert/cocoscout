# frozen_string_literal: true

require "rails_helper"

# Staffing → Availability (the whole staff on a month calendar), the day
# detail, asking people to confirm, and one person's Availability tab.
RSpec.describe "Staffing availability for managers", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:house_role, organization: org, name: "Bar") }

  def staff(name, email:, user: true, roles: [])
    person = create(:person, name: name, email: email, user: (user ? create(:user) : nil))
    member = create(:organization_staff_member, organization: org, person: person, acknowledged_at: 1.week.ago,
                                                first_name: name.split.first, last_name: name.split.last)
    roles.each { |r| StaffRoleQualification.create!(organization_staff_member: member, house_role: r) }
    member
  end

  # A Friday next week, so it's inside the calendar and not in the past.
  let(:day) { Date.current.next_occurring(:friday) + 7 }
  let!(:free_member) { staff("Ada Free", email: "ada@example.com", roles: [ bar ]) }
  let!(:part_member) { staff("Pat Part", email: "pat@example.com") }
  let!(:off_member) { staff("Otto Off", email: "otto@example.com", user: false) }

  before do
    StaffAvailabilityWriter.new(free_member.person).confirm!
    StaffAvailabilityWriter.new(part_member.person)
                           .save_exception!(starts_on: day, ends_on: day, state: "hours", windows: [ { from: "18:00", to: "20:00" } ])
    StaffAvailabilityWriter.new(off_member.person).save_exception!(starts_on: day, ends_on: day, state: "off")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "the page" do
    it "counts who can work each day, and who's confirmed" do
      get manage_staffing_availability_path(month: day.beginning_of_month.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(manage_staffing_availability_day_path(date: day.iso8601))
      expect(response.body).to include("1 of 3")          # only Ada has confirmed
      expect(response.body).to include("Pat Part").and include("Otto Off")
      expect(response.body).to include("Ask them to confirm")
    end

    it "narrows to one role" do
      get manage_staffing_availability_path(role_id: bar.id)
      expect(response.body).to include(manage_staffing_availability_day_path(date: Date.current.iso8601, role_id: bar.id))
    end

    it "is where the scheduling page's Availability link goes" do
      get manage_staffing_scheduling_path
      expect(response.body).to include(manage_staffing_availability_path)
      expect(response.body).not_to include("staff-availability-modal")
    end
  end

  describe "a day" do
    it "groups everyone, with part-day hours and their shifts" do
      shift = Shift.create!(organization: org, house_role: bar, starts_at: day.in_time_zone.change(hour: 19),
                            ends_at: day.in_time_zone.change(hour: 23))
      ShiftAssignment.create!(shift: shift, person: free_member.person)

      get manage_staffing_availability_day_path(date: day.iso8601)

      body = response.body
      expect(body).to include("staff-availability-day")
      expect(body.index("Can work all day")).to be < body.index("Ada Free")
      expect(body.index("Part of the day")).to be < body.index("Pat Part")
      expect(body).to include("6:00 PM – 8:00 PM")
      expect(body.index("Can&#39;t work")).to be < body.index("Otto Off")
      expect(body).to include("Working Bar 7–11 PM")
    end

    it "shows only the role asked for" do
      get manage_staffing_availability_day_path(date: day.iso8601, role_id: bar.id)
      expect(response.body).to include("Ada Free")
      expect(response.body).not_to include("Pat Part")
    end
  end

  describe "asking people to confirm" do
    it "sends the edited draft to the ticked people who can sign in, each by name, from a job" do
      expect {
        post manage_staffing_availability_nudge_path, params: {
          staff_member_ids: [ part_member.id, off_member.id ],
          email_subject: "Check your week, {{first_name}}", email_body: "<p>Hi {{first_name}}</p>"
        }
      }.to have_enqueued_job(StaffAvailabilityNudgeJob)
      expect(flash[:notice]).to include("Asking 1 person")

      expect {
        perform_enqueued_jobs(only: StaffAvailabilityNudgeJob)
      }.to have_enqueued_mail(StaffAvailabilityMailer, :confirm_request)
        .with(part_member, to: "pat@example.com", subject: "Check your week, Pat", body: "<p>Hi Pat</p>")
    end

    it "asks nobody when nobody's ticked" do
      post manage_staffing_availability_nudge_path, params: { email_subject: "x", email_body: "y" }
      expect(flash[:alert]).to eq("Tick at least one person to ask.")
    end
  end

  describe "one person's Availability tab" do
    it "says when they confirmed, or that they never have" do
      get manage_edit_staffing_staff_path(free_member)
      expect(response.body).to include('data-panel="availability"')
      expect(response.body).to include("Up to date through").and include("They confirmed it on")

      get manage_edit_staffing_staff_path(off_member)
      expect(response.body).to include("Never confirmed")

      StaffAvailabilityWriter.new(part_member.person).confirm!
      StaffAvailabilityWriter.new(part_member.person).set_weekdays!([ 0 ], state: "off")
      get manage_edit_staffing_staff_path(part_member)
      expect(response.body).to include("Not confirmed since").and include("Ask them to confirm")
    end

    it "pages its calendar and comes back to the tab" do
      month = (Date.current >> 2).beginning_of_month
      get manage_edit_staffing_staff_path(part_member, availability_month: month.iso8601)
      expect(response.body).to include(month.strftime("%B %Y"))
      expect(response.body).to include('id="availability"')
    end
  end

  it "stamps when someone confirmed" do
    freeze_time do
      StaffAvailabilityWriter.new(part_member.person).confirm!
      expect(part_member.person.reload.availability_confirmed_at).to eq(Time.current)
    end
  end
end

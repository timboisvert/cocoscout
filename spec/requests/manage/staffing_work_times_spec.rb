# frozen_string_literal: true

require "rails_helper"

# Staffing settings → Work times: the regions of the day an organization
# staffs by (Morning / Afternoon / Evening…), which staff mark availability by
# and shifts fall into.
RSpec.describe "Staffing work times", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:owner_person) { create(:person, user: owner) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "starts on the standard Afternoon and Evening" do
    get manage_staffing_settings_section_path(section: "work_times")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Work times")
    expect(response.body).to include("You're on the standard Afternoon (before 5pm) and Evening (5pm on)")
    expect(response.body).to include('name="day_parts[0][name]" value="Afternoon"')
    expect(response.body).to include('name="day_parts[1][name]" value="Evening"')
  end

  it "declares the organization's own regions, in order, keyed by name" do
    patch manage_staffing_settings_path, params: {
      updating_work_times: "1",
      day_parts: {
        "0" => { name: "Morning", starts: "06:00", ends: "12:00" },
        "1" => { name: "Afternoon", starts: "12:00", ends: "17:00" },
        "2" => { name: "Evening", starts: "17:00", ends: "23:59" },
        "3" => { name: "", starts: "", ends: "" }
      }
    }
    expect(response).to redirect_to(manage_staffing_settings_section_path(section: "work_times"))
    expect(org.reload.staffing_day_parts).to eq([
      { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" },
      { "key" => "afternoon", "name" => "Afternoon", "starts" => "12:00", "ends" => "17:00" },
      { "key" => "evening", "name" => "Evening", "starts" => "17:00", "ends" => "24:00" }
    ])
    expect(org.staffing_day_part_for(Time.zone.local(2026, 6, 1, 8, 0))).to eq("morning")
    expect(org.staffing_day_part_for(Time.zone.local(2026, 6, 1, 23, 59))).to eq("evening")
    expect(org.staffing_day_part_for(Time.zone.local(2026, 6, 1, 3, 0))).to be_nil

    get manage_staffing_settings_section_path(section: "work_times")
    expect(response.body).to include('name="day_parts[0][name]" value="Morning"')
    expect(response.body).to include("Clear every row to go back")
  end

  it "won't save a region without a name or times, or two with the same name" do
    patch manage_staffing_settings_path, params: {
      updating_work_times: "1",
      day_parts: { "0" => { name: "Morning", starts: "06:00", ends: "" }, "1" => { name: "", starts: "12:00", ends: "17:00" } }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Morning needs a start and end time.")
    expect(response.body).to include("Every region needs a name.")
    expect(org.reload.staffing_day_parts).to eq([])

    patch manage_staffing_settings_path, params: {
      updating_work_times: "1",
      day_parts: { "0" => { name: "Evening", starts: "17:00", ends: "22:00" }, "1" => { name: " evening ", starts: "22:00", ends: "23:59" } }
    }
    expect(response.body).to include("evening is listed twice.")
    expect(org.reload.staffing_day_parts).to eq([])
  end

  it "clearing every row goes back to the defaults" do
    org.update!(staffing_day_parts: [ { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" } ])
    patch manage_staffing_settings_path, params: { updating_work_times: "1", day_parts: { "0" => { name: "", starts: "", ends: "" } } }
    expect(org.reload.staffing_day_parts).to eq([])
    expect(org.staffing_day_parts_or_default.map { |p| p["key"] }).to eq(%w[afternoon evening])
  end

  describe "what staff see" do
    let!(:staffer) { create(:person, user: create(:user, password: password)) }
    let!(:membership) { create(:organization_staff_member, organization: org, person: staffer) }

    before do
      org.update!(staffing_day_parts: [
        { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" },
        { "key" => "late", "name" => "Late night", "starts" => "22:00", "ends" => "02:00" }
      ])
      post handle_signin_path, params: { email_address: staffer.user.email_address, password: password }
    end

    it "offers the organization's regions on the availability calendar and accepts a mark by them" do
      get my_shifts_path
      expect(response.body).to include("Unavailable Morning")
      expect(response.body).to include("Unavailable Late night")
      expect(response.body).not_to include("Unavailable Afternoon")

      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "late" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(staffer.staff_unavailabilities.find_by(date: "2026-06-10").day_part_key).to eq("late")

      # A region no organization of theirs declares is refused
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-11" ], scope: "afternoon" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

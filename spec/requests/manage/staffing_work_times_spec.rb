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

  it "starts with Morning, Afternoon and Evening on, the rest of the catalog off, and All day always there" do
    get manage_staffing_settings_section_path(section: "work_times")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Work times")
    expect(response.body).to match(/id="day_part_morning"[^>]*checked/)
    expect(response.body).to match(/id="day_part_afternoon"[^>]*checked/)
    expect(response.body).to match(/id="day_part_evening"[^>]*checked/)
    expect(response.body).to include('id="day_part_late_morning"')
    expect(response.body).not_to match(/id="day_part_late_morning"[^>]*checked/)
    expect(response.body).to include("5:00 AM – 9:00 AM")
    expect(response.body).to include("Always offered")
  end

  it "turns on exactly the regions checked, ignoring anything off the catalog" do
    patch manage_staffing_settings_path, params: { updating_work_times: "1", day_part_keys: %w[late_night early_morning morning bogus] }
    expect(response).to redirect_to(manage_staffing_settings_section_path(section: "work_times"))
    # Stored in catalog order, whatever order the boxes were ticked in
    expect(org.reload.staffing_day_parts).to eq(%w[early_morning morning late_night])
    expect(org.staffing_day_parts_or_default.map { |p| p["name"] }).to eq([ "Early morning", "Morning", "Late night" ])
    expect(org.staffing_day_part_keys_for(Time.zone.local(2026, 6, 1, 8, 0))).to eq(%w[early_morning morning])
    expect(org.staffing_day_part_keys_for(Time.zone.local(2026, 6, 1, 23, 0))).to eq(%w[late_night])
    expect(org.staffing_day_part_keys_for(Time.zone.local(2026, 6, 1, 15, 0))).to eq([])
    expect(flash[:notice]).to include("Early morning, Morning, and Late night and all day")
  end

  it "unchecking everything goes back to the defaults" do
    org.update!(staffing_day_parts: %w[late_night])
    patch manage_staffing_settings_path, params: { updating_work_times: "1" }
    expect(org.reload.staffing_day_parts).to eq([])
    expect(org.staffing_day_part_keys).to eq(%w[morning afternoon evening])
  end

  describe "what staff see" do
    let!(:staffer) { create(:person, user: create(:user, password: password)) }
    let!(:membership) { create(:organization_staff_member, organization: org, person: staffer) }

    before do
      org.update!(staffing_day_parts: %w[morning late_night])
      post handle_signin_path, params: { email_address: staffer.user.email_address, password: password }
    end

    it "offers the organization's regions on the availability calendar and accepts a mark by them" do
      get my_shifts_path
      expect(response.body).to include("Unavailable Morning")
      expect(response.body).to include("Unavailable Late night")
      expect(response.body).not_to include("Unavailable Afternoon")

      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "late_night" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(staffer.staff_unavailabilities.find_by(date: "2026-06-10").day_part_key).to eq("late_night")

      # A region no organization of theirs has turned on is refused
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-11" ], scope: "afternoon" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

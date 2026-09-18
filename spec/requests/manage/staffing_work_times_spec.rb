# frozen_string_literal: true

require "rails_helper"

# Staffing settings → Work times: the times of day an organization offers
# (Morning / Afternoon / Evening…) as shortcuts when staff set their hours.
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
    expect(flash[:notice]).to include("Early morning, Morning, and Late night as shortcuts")
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

    it "offers the organization's times of day as shortcuts that fill in their hours" do
      get my_work_availability_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-from="06:00"').and include('data-to="12:00"')
      expect(response.body).to include('data-from="22:00"').and include('data-to="02:00"')
      expect(response.body).to include(">Late night<")
      expect(response.body).not_to include(">Afternoon<")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing generation & display", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }

  # A Tuesday in the current week, 8pm + 9:30pm shows.
  let(:week_start) { Date.current.beginning_of_week }
  let(:show_day) { week_start + 1 }
  let!(:early_show) { create(:show, production: production, date_and_time: show_day.in_time_zone.change(hour: 20), duration_minutes: 90) }
  let!(:late_show)  { create(:show, production: production, date_and_time: show_day.in_time_zone.change(hour: 21, min: 30), duration_minutes: 90) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  before { sign_in(owner) }

  describe "POST generate" do
    it "creates ONE spanning shift for a house role across the day's shows" do
      create(:house_role, organization: org, role_type: :house, default_start_offset_minutes: -60, default_end_offset_minutes: 60)

      expect {
        post manage_generate_staffing_path(week_start: week_start.to_s)
      }.to change(Shift, :count).by(1)

      shift = Shift.last
      # 7pm (60 before first show) → 12:30am (60 after last show's 11pm end).
      expect(shift.starts_at).to eq(early_show.date_and_time - 60.minutes)
      expect(shift.ends_at).to eq(late_show.ends_at + 60.minutes)
      expect(shift.source).to eq(early_show)
    end

    it "creates ONE shift PER show for a show-specific role" do
      role = create(:house_role, organization: org, role_type: :show_specific, default_start_offset_minutes: -30, default_end_offset_minutes: 0)

      expect {
        post manage_generate_staffing_path(week_start: week_start.to_s)
      }.to change(Shift, :count).by(2)

      shifts = Shift.where(house_role: role).order(:starts_at)
      expect(shifts.map(&:source)).to contain_exactly(early_show, late_show)
      expect(shifts.first.starts_at).to eq(early_show.date_and_time - 30.minutes)
      expect(shifts.first.ends_at).to eq(early_show.ends_at)
    end

    it "only generates for the selected shows when show_ids is passed" do
      role = create(:house_role, organization: org, role_type: :show_specific)

      expect {
        post manage_generate_staffing_path(week_start: week_start.to_s), params: { show_ids: [ early_show.id ] }
      }.to change(Shift, :count).by(1)

      shifts = Shift.where(house_role: role)
      expect(shifts.map(&:source)).to contain_exactly(early_show)
    end

    it "spans only the selected shows for a house role" do
      create(:house_role, organization: org, role_type: :house, default_start_offset_minutes: 0, default_end_offset_minutes: 0)

      post manage_generate_staffing_path(week_start: week_start.to_s), params: { show_ids: [ early_show.id ] }

      shift = Shift.last
      # Spans only the early show: its start → its own end.
      expect(shift.starts_at).to eq(early_show.date_and_time)
      expect(shift.ends_at).to eq(early_show.ends_at)
    end

    it "scopes a show-specific role to its venue" do
      other_location = create(:location)
      role = create(:house_role, organization: org, role_type: :show_specific, location: early_show.location)
      late_show.update!(location: other_location)

      post manage_generate_staffing_path(week_start: week_start.to_s)

      shifts = Shift.where(house_role: role)
      expect(shifts.count).to eq(1)
      expect(shifts.first.source).to eq(early_show)
    end
  end

  describe "GET index renders with both role types" do
    it "returns 200 with house and show-specific shifts present" do
      create(:house_role, organization: org, role_type: :house)
      create(:house_role, organization: org, role_type: :show_specific)
      post manage_generate_staffing_path(week_start: week_start.to_s)

      get manage_staffing_index_path(week_start: week_start.to_s)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(production.name) # show-specific label
    end
  end

  describe "doubling up a shift (extra roles)" do
    let(:primary) { create(:house_role, organization: org, name: "Bartender") }
    let(:secondary) { create(:house_role, organization: org, name: "Manager") }
    let(:third) { create(:house_role, organization: org, name: "Security") }
    let!(:shift) { create(:shift, organization: org, house_role: primary) }

    it "sets multiple extra roles via update" do
      patch manage_update_staffing_shift_path(shift), params: { shift: { additional_role_ids: [ secondary.id, third.id ] } }
      shift.reload
      expect(shift.additional_roles).to contain_exactly(secondary, third)
      expect(shift).to be_doubled
      expect(shift.role_label).to eq("Bartender + Manager + Security")
    end

    it "ignores an extra role equal to the primary (silently dropped)" do
      patch manage_update_staffing_shift_path(shift), params: { shift: { additional_role_ids: [ primary.id ] } }
      expect(shift.reload.additional_roles).to be_empty
    end

    it "renders the extra roles on the schedule card" do
      shift.update!(additional_role_ids: [ secondary.id ])
      get manage_staffing_index_path(week_start: shift.starts_at.to_date.beginning_of_week.to_s)
      expect(response.body).to include("Also covers")
      expect(response.body).to include("Manager")
    end

    it "echoes the doubled shift into the extra role's Gantt row" do
      shift.update!(additional_role_ids: [ secondary.id ])
      get manage_staffing_index_path(week_start: shift.starts_at.to_date.beginning_of_week.to_s)
      # The secondary-row echo block carries this title.
      expect(response.body).to include("Also covering Manager")
    end
  end

  describe "cast collision payload" do
    it "maps a cast member to the show day in data-shift-assign-cast-by-day-value" do
      create(:house_role, organization: org, role_type: :house)
      performer = create(:person, name: "Perry Former")
      create(:show_person_role_assignment, show: early_show, assignable: performer)
      post manage_generate_staffing_path(week_start: week_start.to_s)

      get manage_staffing_index_path(week_start: week_start.to_s)
      expect(response).to have_http_status(:ok)

      payload = response.body[/data-shift-assign-cast-by-day-value="([^"]*)"/, 1]
      data = JSON.parse(CGI.unescapeHTML(payload))
      expect(data[show_day.iso8601]).to include(performer.id.to_s)
      expect(response.body).to include("Perry Former") # cast hover list
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Rollout-critical: staff must see ALL of their own shifts (once finalized) and
# NONE of anyone else's, on both My Shifts and the dashboard calendar.
RSpec.describe "Staff shift visibility", type: :request do
  let(:password) { "Password123!" }
  let(:org) { create(:organization) }

  # Next week — entirely in the future — and finalized.
  let(:week_start) { Date.current.beginning_of_week + 7 }
  let!(:finalization) { create(:staffing_finalization, organization: org, week_start: week_start, finalized_at: Time.current) }

  let(:foh)       { create(:house_role, organization: org, name: "FrontOfHouseRole") }
  let(:bartender) { create(:house_role, organization: org, name: "BartenderRole") }

  let(:me) { create(:user, password: password) }
  let!(:my_person) { create(:person, user: me).tap { |p| me.update!(default_person: p) } }
  let(:coworker_user) { create(:user) }
  let!(:coworker) { create(:person, user: coworker_user) }

  def shift_on(day_offset, role)
    day = week_start + day_offset
    create(:shift, organization: org, house_role: role,
                   starts_at: day.in_time_zone.change(hour: 18),
                   ends_at: day.in_time_zone.change(hour: 23))
  end

  let!(:my_shift) { shift_on(2, foh) }
  let!(:my_assignment) { create(:shift_assignment, shift: my_shift, person: my_person) }
  let!(:coworker_shift) { shift_on(2, bartender) }
  let!(:coworker_assignment) { create(:shift_assignment, shift: coworker_shift, person: coworker) }

  before { post handle_signin_path, params: { email_address: me.email_address, password: password } }

  describe "My Shifts" do
    it "shows my finalized shift but not a coworker's" do
      get my_shifts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FrontOfHouseRole")
      expect(response.body).not_to include("BartenderRole")
    end

    it "hides my shifts in a week that hasn't been finalized (draft)" do
      draft_week = week_start + 7 # not finalized
      s = create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "DraftWeekRole"),
                         starts_at: (draft_week + 1).in_time_zone.change(hour: 18),
                         ends_at: (draft_week + 1).in_time_zone.change(hour: 23))
      create(:shift_assignment, shift: s, person: my_person)

      get my_shifts_path
      expect(response.body).not_to include("DraftWeekRole")
    end

    it "hides past shifts" do
      past_week = Date.current.beginning_of_week - 7
      create(:staffing_finalization, organization: org, week_start: past_week, finalized_at: Time.current)
      s = create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "PastWeekRole"),
                         starts_at: (past_week + 1).in_time_zone.change(hour: 18),
                         ends_at: (past_week + 1).in_time_zone.change(hour: 23))
      create(:shift_assignment, shift: s, person: my_person)

      get my_shifts_path
      expect(response.body).not_to include("PastWeekRole")
    end

    it "shows a doubled-up shift with the combined role label" do
      my_shift.update!(secondary_house_role: bartender)
      get my_shifts_path
      expect(response.body).to include("FrontOfHouseRole + BartenderRole")
    end
  end

  describe "Talent dashboard calendar" do
    it "shows my finalized shift and not a coworker's" do
      get my_dashboard_path(scope: "my_assignments")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FrontOfHouseRole")
      expect(response.body).not_to include("BartenderRole")
    end

    it "hides draft-week shifts from the calendar" do
      draft_week = week_start + 7
      s = create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "DraftCalRole"),
                         starts_at: (draft_week + 1).in_time_zone.change(hour: 18),
                         ends_at: (draft_week + 1).in_time_zone.change(hour: 23))
      create(:shift_assignment, shift: s, person: my_person)

      get my_dashboard_path(scope: "my_assignments")
      expect(response.body).not_to include("DraftCalRole")
    end
  end
end

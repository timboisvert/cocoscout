# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Shifts unavailability", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, password: "Password123!") }
  let!(:person) { create(:person, user: user) }

  def sign_in
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  before { sign_in }

  describe "POST /my/shifts/unavailability" do
    it "sets unavailability for a batch of dates" do
      dates = %w[2026-06-10 2026-06-11 2026-06-12]
      post my_create_shift_unavailability_path, params: { dates: dates, scope: "day_shifts" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be(true)
      expect(person.staff_unavailabilities.pluck(:date).map(&:to_s)).to match_array(dates)
      expect(person.staff_unavailabilities.pluck(:scope).uniq).to eq([ "day_shifts" ])
    end

    it "accepts a single date param" do
      post my_create_shift_unavailability_path, params: { date: "2026-06-15", scope: "all_day" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(person.staff_unavailabilities.find_by(date: "2026-06-15").scope).to eq("all_day")
    end

    it "updates the scope of an existing date instead of duplicating" do
      create(:staff_unavailability, person: person, date: Date.new(2026, 6, 20), scope: :all_day)
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-20" ], scope: "evening_shifts" }, as: :json

      expect(person.staff_unavailabilities.where(date: "2026-06-20").count).to eq(1)
      expect(person.staff_unavailabilities.find_by(date: "2026-06-20").scope).to eq("evening_shifts")
    end

    it "clears unavailability for the given dates" do
      create(:staff_unavailability, person: person, date: Date.new(2026, 6, 25))
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-25" ], scope: "clear" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(person.staff_unavailabilities.where(date: "2026-06-25")).to be_empty
    end

    it "rejects an invalid scope" do
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "bogus" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(person.staff_unavailabilities).to be_empty
    end

    it "rejects when no dates are given" do
      post my_create_shift_unavailability_path, params: { scope: "all_day" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "only ever touches the current user's own person" do
      other = create(:person)
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "all_day" }, as: :json
      expect(other.staff_unavailabilities).to be_empty
      expect(person.staff_unavailabilities.count).to eq(1)
    end
  end

  describe "GET /my/shifts" do
    it "renders and embeds existing unavailability entries" do
      create(:staff_unavailability, person: person, date: Date.current + 3.days, scope: :evening_shifts)
      get my_shifts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("evening_shifts")
    end
  end

  describe "GET /my/shifts?tab=all_staff" do
    around { |ex| travel_to(Time.zone.local(2026, 6, 17, 12, 0)) { ex.run } }

    let(:organization) { create(:organization) }
    let(:house_role) { create(:house_role, organization: organization, name: "Bartender") }
    let(:coworker) { create(:person, name: "Casey Coworker") }

    before do
      # Both the current user and a coworker are house staff at the same org.
      create(:organization_staff_member, organization: organization, person: person)
      create(:organization_staff_member, organization: organization, person: coworker)
      create(:staffing_finalization, organization: organization, week_start: Date.current.beginning_of_week)
    end

    def staff_shift_for(assignee)
      shift = create(:shift, organization: organization, house_role: house_role,
                     starts_at: Time.current.change(hour: 18), ends_at: Time.current.change(hour: 22))
      create(:shift_assignment, shift: shift, person: assignee)
      shift
    end

    it "shows other staff members' shifts in the same org" do
      staff_shift_for(coworker)
      get my_shifts_path(tab: "all_staff")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Casey Coworker")
      expect(response.body).to include("Bartender")
    end

    it "hides shifts for weeks that haven't been finalized" do
      StaffingFinalization.delete_all
      staff_shift_for(coworker)
      get my_shifts_path(tab: "all_staff")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Casey Coworker")
    end

    it "does not show shifts from orgs the user is not staff at" do
      other_org = create(:organization)
      other_role = create(:house_role, organization: other_org, name: "Stagehand")
      outsider = create(:person, name: "Outsider Olivia")
      create(:organization_staff_member, organization: other_org, person: outsider)
      create(:staffing_finalization, organization: other_org, week_start: Date.current.beginning_of_week)
      shift = create(:shift, organization: other_org, house_role: other_role,
                     starts_at: Time.current.change(hour: 18), ends_at: Time.current.change(hour: 22))
      create(:shift_assignment, shift: shift, person: outsider)

      get my_shifts_path(tab: "all_staff")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Outsider Olivia")
    end
  end
end

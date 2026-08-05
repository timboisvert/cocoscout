# frozen_string_literal: true

require "rails_helper"

# The scheduling page + shift actions. (The old auto-"Generate shifts" feature
# is gone — shifts are created by hand through the progressive Add-shift modal.)
RSpec.describe "Manage::Staffing scheduling", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
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

  def staff!(person, *roles)
    org.people << person unless org.people.exists?(person.id)
    member = create(:organization_staff_member, organization: org, person: person)
    roles.each { |r| create(:staff_role_qualification, organization_staff_member: member, house_role: r) }
    member
  end

  before { sign_in(owner) }

  describe "the retired Generate shifts feature" do
    it "no longer has a route or a button" do
      # The route is gone (the app's catch-all serves a 404 page rather than
      # letting RoutingError bubble in request specs).
      post "/manage/staffing/generate", params: { week_start: week_start.to_s }
      expect(response).to have_http_status(:not_found)

      create(:house_role, organization: org, role_type: :house)
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("Generate shifts")
    end
  end

  describe "creating a shift from the add-shift modal" do
    let!(:role) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }

    def shift_params(overrides = {})
      { shift: {
        house_role_id: role.id,
        starts_at: show_day.in_time_zone.change(hour: 19).iso8601,
        ends_at: show_day.in_time_zone.change(hour: 23).iso8601,
        required_count: 1, coverage_mode: "needs_assignment",
        source_type: "Show", source_id: early_show.id
      }.merge(overrides) }
    end

    it "creates the shift unassigned when no person is chosen" do
      expect { post manage_create_staffing_shift_path, params: shift_params }
        .to change(Shift, :count).by(1)
      expect(Shift.last.assigned_people).to be_empty
    end

    it "creates the shift AND assigns the chosen qualified person in one go" do
      person = create(:person, name: "Quali Fied")
      staff!(person, role)

      post manage_create_staffing_shift_path, params: shift_params.merge(person_id: person.id)

      shift = Shift.last
      expect(shift.assigned_people).to eq([ person ])
      expect(flash[:notice]).to include("Assigned Quali Fied")
    end

    it "still creates the shift but declines to assign someone unqualified" do
      person = create(:person, name: "Un Qualified") # never staffed
      org.people << person

      expect { post manage_create_staffing_shift_path, params: shift_params.merge(person_id: person.id) }
        .to change(Shift, :count).by(1)
      expect(Shift.last.assigned_people).to be_empty
      expect(flash[:notice]).to include("not on staff or not qualified")
    end
  end

  describe "staying put after an action (no more jump to the top)" do
    let!(:role) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }
    let!(:shift) do
      create(:shift, organization: org, house_role: role, source: early_show,
                     starts_at: early_show.date_and_time, ends_at: late_show.ends_at)
    end

    it "anchors the redirect to the shift's day card" do
      person = create(:person, name: "Anna Chor")
      staff!(person, role)

      post manage_assign_staffing_shift_path(shift), params: { person_id: person.id },
           headers: { "HTTP_REFERER" => manage_staffing_scheduling_url(week_start: week_start.to_s) }

      expect(response).to redirect_to(
        manage_staffing_scheduling_url(week_start: week_start.to_s) + "#day-#{show_day.iso8601}"
      )
    end

    it "anchors a destroy too, using the day captured before deletion" do
      delete manage_destroy_staffing_shift_path(shift),
             headers: { "HTTP_REFERER" => manage_staffing_scheduling_url(week_start: week_start.to_s) }

      expect(response.headers["Location"]).to end_with("#day-#{show_day.iso8601}")
    end

    it "renders the day card with its anchor id" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).to include(%(id="day-#{show_day.iso8601}"))
    end
  end

  describe "the retired gap acknowledgment" do
    it "no longer renders a gap banner between adjacent shifts" do
      role = create(:house_role, organization: org, role_type: :house)
      create(:shift, organization: org, house_role: role, source: early_show,
                     starts_at: show_day.in_time_zone.change(hour: 17), ends_at: show_day.in_time_zone.change(hour: 19))
      create(:shift, organization: org, house_role: role, source: early_show,
                     starts_at: show_day.in_time_zone.change(hour: 21), ends_at: show_day.in_time_zone.change(hour: 23))

      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("uncovered)")
      expect(response.body).not_to include("acknowledge_gap")
    end
  end

  describe "the coverage assistant" do
    let!(:tech) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }

    it "stays quiet when the setting is off" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("needs Booth Tech")
    end

    context "with the setting on" do
      before { org.update!(alert_uncovered_show_roles: true) }

      it "flags shows with no staffed tech shift, naming the role" do
        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).to include("needs Booth Tech")
      end

      it "clears the flag once a staffed shift covers the show" do
        person = create(:person)
        staff!(person, tech)
        [ early_show, late_show ].each do |show|
          shift = create(:shift, organization: org, house_role: tech, source: show,
                                 starts_at: show.date_and_time, ends_at: show.ends_at)
          create(:shift_assignment, shift: shift, person: person)
        end

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).not_to include("needs Booth Tech")
      end

      it "an unstaffed shift isn't coverage — the flag stays" do
        create(:shift, organization: org, house_role: tech, source: early_show,
                       starts_at: early_show.date_and_time, ends_at: early_show.ends_at)

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).to include("needs Booth Tech")
      end

      it "ignores roles scoped to a different venue" do
        tech.update!(location: create(:location))

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).not_to include("needs Booth Tech")
      end
    end
  end

  describe "settings: the coverage toggle" do
    it "turns the assistant on and off from Staffing settings" do
      patch manage_staffing_settings_path, params: { updating_coverage: "1", alert_uncovered_show_roles: "1" }
      expect(org.reload.alert_uncovered_show_roles).to be(true)

      patch manage_staffing_settings_path, params: { updating_coverage: "1" }
      expect(org.reload.alert_uncovered_show_roles).to be(false)
    end
  end

  describe "GET index renders with both role types" do
    it "returns 200 with house and show-specific shifts present" do
      house = create(:house_role, organization: org, role_type: :house)
      tech = create(:house_role, organization: org, role_type: :show_specific)
      create(:shift, organization: org, house_role: house, source: early_show,
                     starts_at: early_show.date_and_time, ends_at: late_show.ends_at)
      create(:shift, organization: org, house_role: tech, source: early_show,
                     starts_at: early_show.date_and_time, ends_at: early_show.ends_at)

      get manage_staffing_scheduling_path(week_start: week_start.to_s)
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
      get manage_staffing_scheduling_path(week_start: shift.starts_at.to_date.beginning_of_week.to_s)
      expect(response.body).to include("Also covers")
      expect(response.body).to include("Manager")
    end

    it "echoes the doubled shift into the extra role's Gantt row" do
      shift.update!(additional_role_ids: [ secondary.id ])
      get manage_staffing_scheduling_path(week_start: shift.starts_at.to_date.beginning_of_week.to_s)
      # The secondary-row echo block carries this title.
      expect(response.body).to include("Also covering Manager")
    end
  end

  describe "cast collision payload" do
    it "maps a cast member to the show day in data-shift-assign-cast-by-day-value" do
      house = create(:house_role, organization: org, role_type: :house)
      performer = create(:person, name: "Perry Former")
      create(:show_person_role_assignment, show: early_show, assignable: performer)
      create(:shift, organization: org, house_role: house, source: early_show,
                     starts_at: early_show.date_and_time, ends_at: late_show.ends_at)

      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response).to have_http_status(:ok)

      payload = response.body[/data-shift-assign-cast-by-day-value="([^"]*)"/, 1]
      data = JSON.parse(CGI.unescapeHTML(payload))
      expect(data[show_day.iso8601]).to include(performer.id.to_s)
      expect(response.body).to include("Perry Former") # cast hover list
    end
  end
end

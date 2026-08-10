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

  # Every face on this page costs three queries to resolve unless the headshot
  # chain is preloaded — and the same person is drawn several times over. The
  # absolute count isn't the point; that it stops growing with the roster is.
  describe "the cost of the scheduling page" do
    # One shift per role per slot is enforced by a unique index, so a busier week
    # means more people on the shift — which is the real shape anyway.
    def staffed_person!(role, shift, name)
      person = create(:person, name: name)
      staff!(person, role)
      create(:shift_assignment, shift: shift, person: person)
      create(:show_person_role_assignment, show: early_show, assignable: person)
      person
    end

    it "doesn't grow with the number of staff on the week" do
      role = create(:house_role, organization: org, role_type: :house)
      shift = create(:shift, organization: org, house_role: role, source: early_show,
                             required_count: 8,
                             starts_at: early_show.date_and_time, ends_at: early_show.ends_at)
      staffed_person!(role, shift, "First Staffer")
      get manage_staffing_scheduling_path(week_start: week_start.to_s) # warm
      baseline = count_queries { get manage_staffing_scheduling_path(week_start: week_start.to_s) }

      6.times { |i| staffed_person!(role, shift, "Staffer #{i}") }
      scaled = count_queries { get manage_staffing_scheduling_path(week_start: week_start.to_s) }

      expect(scaled - baseline).to be <= 1
    end
  end

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

  # Turbo only morphs the page — patching what changed, leaving scroll alone —
  # when a form redirects to the exact URL it was submitted from. An anchor, a
  # dropped query param, anything: the match fails and the manager gets a full
  # re-render from the top of the week. So these assert byte-identical returns.
  describe "staying put after an action (morph, not reload)" do
    let!(:role) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }
    let!(:shift) do
      create(:shift, organization: org, house_role: role, source: early_show,
                     starts_at: early_show.date_and_time, ends_at: late_show.ends_at)
    end
    let(:page_url) { manage_staffing_scheduling_url(week_start: week_start.to_s) }

    it "returns an assign to the identical URL, with no anchor" do
      person = create(:person, name: "Anna Chor")
      staff!(person, role)

      post manage_assign_staffing_shift_path(shift), params: { person_id: person.id },
           headers: { "HTTP_REFERER" => page_url }

      expect(response).to redirect_to(page_url)
      expect(response.headers["Location"]).not_to include("#")
    end

    it "returns a destroy to the identical URL too" do
      delete manage_destroy_staffing_shift_path(shift), headers: { "HTTP_REFERER" => page_url }

      expect(response).to redirect_to(page_url)
    end

    it "keeps whatever week the manager was on" do
      other_week = (week_start + 7).to_s
      other_url = manage_staffing_scheduling_url(week_start: other_week)

      delete manage_destroy_staffing_shift_path(shift), headers: { "HTTP_REFERER" => other_url }

      expect(response).to redirect_to(other_url)
    end

    it "falls back to the schedule when there's no referer to return to" do
      delete manage_destroy_staffing_shift_path(shift)
      expect(response).to redirect_to(manage_staffing_scheduling_url)
    end

    it "declares morphing so Turbo patches in place instead of re-rendering" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)

      expect(response.body).to include(%(name="turbo-refresh-method" content="morph"))
      expect(response.body).to include(%(name="turbo-refresh-scroll" content="preserve"))
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

  describe "Role Call" do
    let!(:tech) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }

    it "stays quiet when the setting is off" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("needs Booth Tech")
    end

    it "is absent from the show popover and panel entirely when the setting is off" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("Role Call")
      expect(response.body).not_to include("not covered yet")
      expect(response.body).not_to include("Not needed here")
    end

    context "with the setting on" do
      before { org.update!(alert_uncovered_show_roles: true) }

      it "flags shows with no staffed tech shift, naming the role" do
        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).to include("needs Booth Tech")
      end

      it "brands the popover and panel, and links through to its settings" do
        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).to include("Role Call")
        expect(response.body).to include("Still needs Booth Tech")   # popover summary
        expect(response.body).to include("not covered yet")          # panel row
        expect(response.body).to include(manage_staffing_settings_section_path(section: "role_call"))
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

      it "skips roles a show marked as not needed, and offers to re-enable each" do
        [ early_show, late_show ].each { |s| s.update!(staffing_coverage_exempt_role_ids: [ tech.id ]) }

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).not_to include("needs Booth Tech")
        expect(response.body).to include("not needed for this show")
        expect(response.body).to include("Needs it again")
      end

      it "a role kept out of Role Call never flags a show" do
        tech.update!(include_in_role_call: false)

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).not_to include("needs Booth Tech")
      end

      it "a role kept out of Role Call isn't offered as excusable either" do
        door = create(:house_role, organization: org, name: "Door Person", role_type: :show_specific)
        tech.update!(include_in_role_call: false)

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        # The panel lists every checked role with its own excuse/re-enable form.
        # An opted-out role is out of the feature entirely, not merely covered,
        # so it gets no row — asserted on the form's role_id, since the role
        # name also appears in the schedule grid.
        expect(response.body).to include("role_id=#{door.id}")
        expect(response.body).not_to include("role_id=#{tech.id}")
      end

      it "an exempt role stays exempt while other roles still flag" do
        door = create(:house_role, organization: org, name: "Door Person", role_type: :show_specific)
        [ early_show, late_show ].each { |s| s.update!(staffing_coverage_exempt_role_ids: [ tech.id ]) }

        get manage_staffing_scheduling_path(week_start: week_start.to_s)
        expect(response.body).not_to include("needs Booth Tech")
        expect(response.body).to include("needs Door Person")
      end
    end
  end

  describe "the per-role coverage opt-out" do
    let!(:tech) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
    let!(:door) { create(:house_role, organization: org, name: "Door Person", role_type: :show_specific) }

    it "flips one role at a time, returning to the page it was clicked from" do
      page_url = manage_staffing_scheduling_url(week_start: week_start.to_s)

      patch manage_staffing_show_coverage_exempt_path(early_show, role_id: tech.id, exempt: "1"),
            headers: { "HTTP_REFERER" => page_url }
      expect(early_show.reload.staffing_coverage_exempt_role_ids).to eq([ tech.id ])
      expect(response).to redirect_to(page_url)

      patch manage_staffing_show_coverage_exempt_path(early_show, role_id: door.id, exempt: "1")
      expect(early_show.reload.staffing_coverage_exempt_role_ids).to contain_exactly(tech.id, door.id)

      patch manage_staffing_show_coverage_exempt_path(early_show, role_id: tech.id)
      expect(early_show.reload.staffing_coverage_exempt_role_ids).to eq([ door.id ])
    end

    it "refuses a show belonging to another organization" do
      foreign_show = create(:show, production: create(:production, organization: create(:organization, owner: create(:user))))

      patch manage_staffing_show_coverage_exempt_path(foreign_show, role_id: tech.id, exempt: "1")
      expect(foreign_show.reload.staffing_coverage_exempt_role_ids).to eq([])
    end

    it "refuses a role belonging to another organization" do
      foreign_role = create(:house_role, organization: create(:organization, owner: create(:user)), role_type: :show_specific)

      patch manage_staffing_show_coverage_exempt_path(early_show, role_id: foreign_role.id, exempt: "1")
      expect(early_show.reload.staffing_coverage_exempt_role_ids).to eq([])
    end
  end

  describe "settings: the Role Call section" do
    it "turns Role Call on and off from Staffing settings" do
      patch manage_staffing_settings_path, params: { updating_coverage: "1", alert_uncovered_show_roles: "1" }
      expect(org.reload.alert_uncovered_show_roles).to be(true)
      expect(response).to redirect_to(manage_staffing_settings_section_path(section: "role_call"))

      patch manage_staffing_settings_path, params: { updating_coverage: "1" }
      expect(org.reload.alert_uncovered_show_roles).to be(false)
    end

    it "renders the named section under its own tab" do
      get manage_staffing_settings_section_path(section: "role_call")
      expect(response.body).to include("Role Call")
      expect(response.body).to include("Run Role Call on my shows")
    end

    describe "the roster of checked roles" do
      let!(:tech) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
      let!(:video) { create(:house_role, organization: org, name: "Videographer", role_type: :show_specific) }
      let!(:bar) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }

      it "isn't shown while Role Call is off" do
        get manage_staffing_settings_section_path(section: "role_call")
        expect(response.body).not_to include("Which roles get checked")
      end

      context "with Role Call on" do
        before { org.update!(alert_uncovered_show_roles: true) }

        it "lists per-show roles only, checked by default" do
          get manage_staffing_settings_section_path(section: "role_call")
          expect(response.body).to include("Which roles get checked")
          expect(response.body).to include("Booth Tech")
          expect(response.body).to include("Videographer")
          # A house role is never checked by Role Call, so it has no switch here.
          expect(response.body).not_to include("role_call_role_#{bar.id}")
        end

        it "leaves out the roles that weren't submitted, and puts back the ones that were" do
          patch manage_staffing_settings_path,
                params: { updating_role_call_roles: "1", role_call_role_ids: [ tech.id.to_s ] }

          expect(tech.reload.include_in_role_call).to be(true)
          expect(video.reload.include_in_role_call).to be(false)
          expect(response).to redirect_to(manage_staffing_settings_section_path(section: "role_call"))
          expect(flash[:notice]).to include("1 role")

          patch manage_staffing_settings_path,
                params: { updating_role_call_roles: "1", role_call_role_ids: [ tech.id.to_s, video.id.to_s ] }
          expect(video.reload.include_in_role_call).to be(true)
        end

        it "an all-unchecked submit takes every role out rather than doing nothing" do
          patch manage_staffing_settings_path, params: { updating_role_call_roles: "1" }

          expect(tech.reload.include_in_role_call).to be(false)
          expect(video.reload.include_in_role_call).to be(false)
        end

        it "can't reach a house role or another org's role" do
          foreign = create(:house_role, organization: create(:organization, owner: create(:user)),
                                        role_type: :show_specific, include_in_role_call: false)

          patch manage_staffing_settings_path,
                params: { updating_role_call_roles: "1", role_call_role_ids: [ bar.id.to_s, foreign.id.to_s ] }

          expect(foreign.reload.include_in_role_call).to be(false)
          expect(bar.reload.include_in_role_call).to be(true)
        end
      end
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

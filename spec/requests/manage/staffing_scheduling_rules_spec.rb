# frozen_string_literal: true

require "rails_helper"

# Regulars: standing scheduling rules, their CRUD page, the settings toggle,
# and the weekly bulk-apply from the Scheduling page.
RSpec.describe "Manage::Staffing::SchedulingRules", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Starlet's Burlesque") }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:tuesday) { week_start + 1 }
  let(:tech_role) { create(:house_role, organization: org, name: "Tech", role_type: :show_specific) }

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

  describe "access" do
    it "blocks users who aren't owners or managers" do
      viewer = create(:user, password: password)
      create(:organization_role, user: viewer, organization: org) # viewer, not manager
      sign_in(viewer)

      get manage_staffing_scheduling_rules_path
      expect(response).to redirect_to(manage_path)
    end
  end

  describe "the rules page" do
    let(:person) { create(:person, name: "Haley") }

    before { staff!(person, tech_role) }

    it "renders both rule shapes, and nudges when the toggle is off" do
      create(:scheduling_rule, organization: org, person: person,
                               house_role: tech_role, production: production)
      camille = create(:person, name: "Camille")
      staff!(camille, tech_role)
      create(:scheduling_rule, :weekday, organization: org, person: camille, house_role: tech_role)

      get manage_staffing_scheduling_rules_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Haley").and include("Starlet&#39;s Burlesque")
      expect(response.body).to include("Camille").and include("Thursdays 6:00 PM – 10:00 PM")
      expect(response.body).to include("Regulars is currently turned off")
    end

    it "renders the settings section" do
      get manage_staffing_settings_section_path(section: "regulars")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Use Regulars on my schedule")
    end
  end

  describe "CRUD" do
    let(:person) { create(:person, name: "Haley") }

    before { staff!(person, tech_role) }

    it "creates a production-anchored rule" do
      post manage_create_staffing_scheduling_rule_path, params: {
        scheduling_rule: { person_id: person.id, rule_type: "production_anchored",
                           house_role_id: tech_role.id, production_id: production.id }
      }

      expect(response).to redirect_to(manage_staffing_scheduling_rules_path)
      rule = org.scheduling_rules.sole
      expect(rule).to be_production_anchored
      expect(rule.production).to eq(production)
    end

    it "creates a weekday rule and ignores production leftovers" do
      post manage_create_staffing_scheduling_rule_path, params: {
        scheduling_rule: { person_id: person.id, rule_type: "weekday",
                           house_role_id: tech_role.id, production_id: production.id,
                           day_of_week: 4, starts_local_time: "18:00", ends_local_time: "22:00" }
      }

      rule = org.scheduling_rules.sole
      expect(rule).to be_weekday
      expect(rule.production_id).to be_nil
      expect(rule.day_of_week).to eq(4)
    end

    it "refuses a production belonging to another organization" do
      foreign_production = create(:production)

      post manage_create_staffing_scheduling_rule_path, params: {
        scheduling_rule: { person_id: person.id, rule_type: "production_anchored",
                           house_role_id: tech_role.id, production_id: foreign_production.id }
      }

      expect(org.scheduling_rules.count).to eq(0)
      expect(flash[:alert]).to include("Couldn't add")
    end

    it "updates a rule in place" do
      rule = create(:scheduling_rule, organization: org, person: person,
                                      house_role: tech_role, production: production)

      patch manage_update_staffing_scheduling_rule_path(rule), params: {
        scheduling_rule: { person_id: person.id, rule_type: "weekday",
                           house_role_id: tech_role.id,
                           day_of_week: 2, starts_local_time: "17:00", ends_local_time: "23:00" }
      }

      expect(rule.reload).to be_weekday
      expect(rule.production_id).to be_nil
    end

    it "deletes a rule" do
      rule = create(:scheduling_rule, organization: org, person: person,
                                      house_role: tech_role, production: production)

      delete manage_destroy_staffing_scheduling_rule_path(rule)
      expect(org.scheduling_rules.count).to eq(0)
    end

    it "won't touch another org's rule" do
      foreign_rule = create(:scheduling_rule)

      delete manage_destroy_staffing_scheduling_rule_path(foreign_rule)
      expect(response).to have_http_status(:not_found)
      expect(SchedulingRule.exists?(foreign_rule.id)).to be(true)
    end
  end

  describe "the settings toggle" do
    it "turns Regulars on and off via the marker param" do
      patch manage_staffing_settings_path, params: { updating_regulars: "1", staffing_regulars_enabled: "1" }
      expect(org.reload.staffing_regulars_enabled).to be(true)

      patch manage_staffing_settings_path, params: { updating_regulars: "1" }
      expect(org.reload.staffing_regulars_enabled).to be(false)
    end
  end

  describe "the scheduling page" do
    let(:person) { create(:person, name: "Haley") }
    let!(:show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }

    before do
      staff!(person, tech_role)
      create(:scheduling_rule, organization: org, person: person,
                               house_role: tech_role, production: production)
    end

    it "offers the apply button and modal when Regulars is on and rules match" do
      org.update!(staffing_regulars_enabled: true)

      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).to include("Apply regulars (1)")
      expect(response.body).to include("regulars-apply-modal")
    end

    it "shows nothing of Regulars when the toggle is off" do
      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).not_to include("Apply regulars")
      expect(response.body).not_to include("regulars-apply-modal")
    end

    it "flags an unavailable person in the modal, unchecked but still offered" do
      org.update!(staffing_regulars_enabled: true)
      create(:staff_unavailability, person: person, date: tuesday)

      get manage_staffing_scheduling_path(week_start: week_start.to_s)
      expect(response.body).to include("Marked unavailable")
    end
  end

  describe "apply" do
    let(:person) { create(:person, name: "Haley") }
    let!(:show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }
    let!(:rule) do
      staff!(person, tech_role)
      create(:scheduling_rule, organization: org, person: person,
                               house_role: tech_role, production: production)
    end

    def match_keys
      SchedulingRuleMatcher.new(organization: org, week_start: week_start).matches.map(&:key)
    end

    it "creates the checked shifts and redirects back to scheduling" do
      org.update!(staffing_regulars_enabled: true)

      post manage_apply_staffing_scheduling_rules_path,
           params: { week_start: week_start.iso8601, match_keys: match_keys },
           headers: { "HTTP_REFERER" => manage_staffing_scheduling_url(week_start: week_start.to_s) }

      expect(response).to redirect_to(manage_staffing_scheduling_url(week_start: week_start.to_s))
      shift = org.shifts.sole
      expect(shift.source).to eq(show)
      expect(shift.assigned_people).to eq([ person ])
      expect(flash[:notice]).to include("Scheduled 1 regular")
    end

    it "refuses to apply when the toggle is off" do
      post manage_apply_staffing_scheduling_rules_path,
           params: { week_start: week_start.iso8601, match_keys: match_keys }

      expect(org.shifts.count).to eq(0)
      expect(flash[:alert]).to include("isn't turned on")
    end

    it "rejects an unparseable week" do
      org.update!(staffing_regulars_enabled: true)

      post manage_apply_staffing_scheduling_rules_path,
           params: { week_start: "not-a-date", match_keys: match_keys }

      expect(org.shifts.count).to eq(0)
      expect(flash[:alert]).to include("which week")
    end
  end
end

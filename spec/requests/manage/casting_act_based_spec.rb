# frozen_string_literal: true

require "rails_helper"

# Casting an act-based show: the board renders the running order (numbered
# acts, intermission as a divider), a person can hold two acts, progress
# counts castable slots only, and the notification copy says "act".
RSpec.describe "Manage::Casting act-based board", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, casting_mode: "act_based") }
  let(:show) { create(:show, production: production) }

  # Lineup: Magic, Variety, — Intermission —, Magic (numbers 1, 2, 3; the break is unnumbered)
  let!(:magic_one) { create(:role, production: production, name: "Magic", position: 0) }
  let!(:variety)   { create(:role, production: production, name: "Variety", position: 1) }
  let!(:intermission) { create(:role, production: production, name: "Intermission", category: "break", position: 2) }
  let!(:magic_two) { create(:role, production: production, name: "Magic", position: 3) }

  let!(:performer) { create(:person, user: create(:user)).tap { |p| org.people << p } }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "GET show cast" do
    it "renders the lineup with numbering that skips the break, and the break as a divider" do
      get manage_casting_show_cast_path(production, show)
      expect(response).to have_http_status(:ok)

      expect(response.body).to include("Lineup")
      # data-role-name carries the display label the JS uses in modals/toasts
      expect(response.body).to include('data-role-name="Act 1 · Magic"')
      expect(response.body).to include('data-role-name="Act 2 · Variety"')
      expect(response.body).to include('data-role-name="Act 3 · Magic"')
      expect(response.body).not_to include('data-role-name="Act 4')

      # The break is a divider, never a drop target
      expect(response.body).to include('data-role-break="true"')
      expect(response.body).not_to include(%(data-role-name="Intermission"))

      # Act-mode copy
      expect(response.body).to include("Cast this act")
      expect(response.body).to include("Edit lineup")
      expect(response.body).to include("0 of 3 acts have been cast")
      expect(response.body).to include('data-drop-role-unit-value="act"')
    end
  end

  describe "assigning the same person to two acts" do
    it "works through the existing assign endpoint and counts 3 slots, not 4" do
      post manage_casting_show_assign_person_path(production, show),
           params: { person_id: performer.id, role_id: magic_one.id }
      expect(response).to have_http_status(:ok)

      post manage_casting_show_assign_person_path(production, show),
           params: { person_id: performer.id, role_id: magic_two.id }
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["progress"]["role_count"]).to eq(3)
      expect(json["progress"]["assignment_count"]).to eq(2)

      expect(show.show_person_role_assignments.where(assignable: performer).count).to eq(2)
      expect(show.casting_progress).to include(total: 3, filled: 2)
      expect(show.fully_cast?).to be(false)
    end

    it "refuses to cast anyone into the intermission" do
      post manage_casting_show_assign_person_path(production, show),
           params: { person_id: performer.id, role_id: intermission.id }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(show.show_person_role_assignments.count).to eq(0)
    end
  end

  describe "cast notification variables" do
    before do
      create(:show_person_role_assignment, show: show, role: magic_one, assignable: performer)
      create(:show_person_role_assignment, show: show, role: magic_two, assignable: performer)
    end

    it "fills casting_unit with 'act' and role_names with the numbered acts" do
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: [ "Person:#{performer.id}" ],
        cast_email_draft: {
          title: "Your {{casting_unit}} in {{production_name}}",
          body: "<div>Your {{casting_units}}: {{role_names}}</div>"
        }
      }

      msg = Message.order(:created_at).last
      expect(msg).to be_present
      expect(msg.subject).to eq("Your act in #{production.name}")
      expect(msg.body.to_plain_text).to include("Your acts: Act 1 · Magic, Act 3 · Magic")
    end

    it "uses the act vocabulary in a removed-from-cast notice too" do
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: [ "Person:#{performer.id}" ], cast_email_draft: { title: "Hi", body: "x" }
      }
      show.show_person_role_assignments.where(assignable: performer).destroy_all

      post manage_casting_show_notify_path(production, show), params: {
        removed_keys: [ "Person:#{performer.id}" ],
        removed_email_draft: { title: "Change to your {{casting_unit}}", body: "<div>Released: {{role_names}}</div>" }
      }

      msg = Message.order(:created_at).last
      expect(msg.subject).to eq("Change to your act")
      # Both of their acts were "Magic"; the notice names whichever was notified last
      expect(msg.body.to_plain_text).to match(/Released: Act [13] · Magic/)
    end
  end

  describe "everywhere else the cast is shown" do
    before do
      create(:show_person_role_assignment, show: show, role: magic_one, assignable: performer)
      create(:show_person_role_assignment, show: show, role: magic_two, assignable: performer)
    end

    it "labels the casting index cast card with numbered acts and no slot for the break" do
      get manage_casting_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 1 · Magic")
      expect(response.body).to include("Act 3 · Magic")
      expect(response.body).to include("Act 2 · Variety - Not Cast")
      expect(response.body).not_to include("Intermission - Not Cast")
    end

    it "labels the shows list cast summary the same way" do
      get manage_production_shows_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 1 · Magic")
      expect(response.body).to include("Act 2 · Variety (not assigned)")
      expect(response.body).not_to include("Intermission (not assigned)")

      get manage_shows_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 3 · Magic")
    end

    it "labels the finalized board and the performer's own show page" do
      show.finalize_casting!  # finalized shows are visible to performers
      get manage_casting_show_cast_path(production, show)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 1 · Magic")
      expect(response.body).not_to include("Intermission")

      get my_show_path(show)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 3 · Magic")
    end
  end

  describe "per-show lineup tweaks (custom roles) accept breaks only in act mode" do
    it "creates an intermission row for an act-based show" do
      show.update!(use_custom_roles: true)
      post manage_show_roles_path(production, show),
           params: { show_role: { name: "Intermission", category: "break", quantity: 1 } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(show.custom_roles.reload.map(&:category)).to eq([ "break" ])
    end

    context "for a role-based production" do
      let(:production) { create(:production, organization: org, casting_mode: "role_based") }
      let!(:magic_one) { nil }
      let!(:variety) { nil }
      let!(:intermission) { nil }
      let!(:magic_two) { nil }

      it "quietly turns a break into a performing role" do
        show.update!(use_custom_roles: true)
        post manage_show_roles_path(production, show),
             params: { show_role: { name: "Intermission", category: "break", quantity: 1 } }, as: :json
        expect(response).to have_http_status(:ok)
        expect(show.custom_roles.reload.map(&:category)).to eq([ "performing" ])
      end
    end
  end

  describe "role-based productions are unchanged" do
    let(:production) { create(:production, organization: org, casting_mode: "role_based") }
    let!(:magic_one) { create(:role, production: production, name: "Magic", position: 0) }
    let!(:variety)   { create(:role, production: production, name: "Variety", position: 1) }
    let!(:intermission) { nil }
    let!(:magic_two) { nil }

    it "keeps the role vocabulary and plain names" do
      get manage_casting_show_cast_path(production, show)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-role-name="Magic"')
      expect(response.body).to include("0 of 2 roles have been cast")
      expect(response.body).to include("Manage Roles")
      expect(response.body).not_to include("Cast this act")
      expect(response.body).to include('data-drop-role-unit-value="role"')
    end
  end

  describe "the pay-by-act nudge on the production's casting page" do
    context "on a Pro org" do
      let!(:org) { create(:organization, :pro, owner: owner) }

      it "nudges an act-based production that has no payout calculation yet, into the calculation wizard" do
        get manage_casting_production_path(production)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pay by act?")
        expect(response.body).to include("Set up per-act pay")
        expect(response.body).to include(ERB::Util.html_escape(manage_money_payout_calculation_wizard_start_path(
          production_id: production.id, return_to: manage_casting_production_path(production)
        )))
        expect(response.body).not_to include("preset=per_act")
      end

      it "goes quiet once a calculation is the production's default" do
        scheme = PayoutScheme.create!(organization: org, name: "Act Pay",
                                      rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 40 } })
        scheme.add_default_for_production!(production, effective_from: Date.current)

        get manage_casting_production_path(production)
        expect(response.body).not_to include("Pay by act?")
      end
    end

    it "never nudges an org without Money" do
      get manage_casting_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Pay by act?")
    end
  end
end

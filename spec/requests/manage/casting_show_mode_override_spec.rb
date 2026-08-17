# frozen_string_literal: true

require "rails_helper"

# A show may override its production's casting style (shows.casting_mode,
# nil = inherit) the way it overrides casting_source. One variety night inside
# a role-based production casts by acts — numbered lineup, act vocabulary,
# per-act pay from the lineup — while its siblings stay role-based.
RSpec.describe "Manage::Casting per-show casting-mode override", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, casting_mode: "role_based") }

  let!(:variety_night) { create(:show, production: production, casting_mode: "act_based", date_and_time: 3.days.from_now) }
  let!(:plain_night)   { create(:show, production: production, date_and_time: 4.days.from_now) }

  # A role-based production keeps one role per name — three distinct roles
  # that read as a running order on the overridden night.
  let!(:magic)   { create(:role, production: production, name: "Magic", position: 0) }
  let!(:variety) { create(:role, production: production, name: "Variety", position: 1) }
  let!(:aerial)  { create(:role, production: production, name: "Aerial", position: 2) }

  let!(:performer) { create(:person, name: "Acty Ada", user: create(:user)).tap { |p| org.people << p } }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the casting board" do
    it "renders the overridden show as a numbered lineup with act vocabulary" do
      get manage_casting_show_cast_path(production, variety_night)
      expect(response).to have_http_status(:ok)

      expect(response.body).to include('data-role-name="Act 1 · Magic"')
      expect(response.body).to include('data-role-name="Act 2 · Variety"')
      expect(response.body).to include('data-role-name="Act 3 · Aerial"')
      expect(response.body).to include("Cast this act")
      expect(response.body).to include("Edit lineup")
      expect(response.body).to include("0 of 3 acts have been cast")
      expect(response.body).to include('data-drop-role-unit-value="act"')
      expect(response.body).to include('data-show-roles-modal-act-based-value="true"')
    end

    it "leaves the production's other show on the role UI" do
      get manage_casting_show_cast_path(production, plain_night)
      expect(response).to have_http_status(:ok)

      expect(response.body).to include('data-role-name="Magic"')
      expect(response.body).not_to include("Act 1 · Magic")
      expect(response.body).to include("0 of 3 roles have been cast")
      expect(response.body).to include("Manage Roles")
      expect(response.body).not_to include("Cast this act")
      expect(response.body).to include('data-drop-role-unit-value="role"')
    end

    it "offers the casting-style override in the casting settings modal" do
      get manage_casting_show_cast_path(production, variety_night)
      expect(response.body).to include("Override the production's casting style for this event")
      expect(response.body).to include('name="show[casting_mode]"')
      expect(response.body).to include("Assignments are kept either way")
      expect(response.body).to include("this event gets its own lineup so the production's roles stay as they are")
    end
  end

  describe "everywhere else the cast is shown" do
    before do
      create(:show_person_role_assignment, show: variety_night, role: magic, assignable: performer)
      create(:show_person_role_assignment, show: plain_night, role: magic, assignable: performer)
    end

    it "numbers acts on the overridden show's cast card and plain names on the other" do
      get manage_casting_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 1 · Magic")
      expect(response.body).to include("Act 2 · Variety - Not Cast")
      expect(response.body).to include("Variety - Not Cast")
    end

    it "labels the shows list per show" do
      get manage_production_shows_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Act 1 · Magic")
      expect(response.body).to include("Act 2 · Variety (not assigned)")
      expect(response.body).to include("Variety (not assigned)")
    end

    it "labels the performer's own show pages per show" do
      variety_night.finalize_casting!
      plain_night.finalize_casting!

      # A person's own assignments read "Magic (Act 1)" on the act-mode night
      get my_show_path(variety_night)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Magic (Act 1)")

      get my_show_path(plain_night)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("(Act 1)")
      expect(response.body).not_to include("Act 1 · Magic")
    end

    it "uses the act vocabulary in the overridden show's cast notification only" do
      post manage_casting_show_notify_path(production, variety_night), params: {
        assignable_keys: [ "Person:#{performer.id}" ],
        cast_email_draft: { title: "Your {{casting_unit}}", body: "<div>{{role_names}}</div>" }
      }
      msg = Message.order(:created_at).last
      expect(msg.subject).to eq("Your act")
      expect(msg.body.to_plain_text).to include("Magic (Act 1)")

      post manage_casting_show_notify_path(production, plain_night), params: {
        assignable_keys: [ "Person:#{performer.id}" ],
        cast_email_draft: { title: "Your {{casting_unit}}", body: "<div>{{role_names}}</div>" }
      }
      msg = Message.order(:created_at).last
      expect(msg.subject).to eq("Your role")
      expect(msg.body.to_plain_text).to include("Magic")
      expect(msg.body.to_plain_text).not_to include("Act 1")
    end
  end

  describe "per-show lineup tweaks on the overridden show" do
    it "accepts an intermission row (breaks belong to act-based lineups)" do
      variety_night.update!(use_custom_roles: true)
      post manage_show_roles_path(production, variety_night),
           params: { show_role: { name: "Intermission", category: "break", quantity: 1 } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(variety_night.custom_roles.reload.map(&:category)).to eq([ "break" ])
    end

    it "still turns a break into a performing role on the role-based sibling" do
      plain_night.update!(use_custom_roles: true)
      post manage_show_roles_path(production, plain_night),
           params: { show_role: { name: "Intermission", category: "break", quantity: 1 } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(plain_night.custom_roles.reload.map(&:category)).to eq([ "performing" ])
    end

    it "lets the overridden show's custom lineup repeat a name" do
      variety_night.update!(use_custom_roles: true)
      create(:role, production: production, show: variety_night, name: "Magic", position: 0)
      second = build(:role, production: production, show: variety_night, name: "Magic", position: 1)
      expect(second).to be_valid
    end
  end

  describe "per-act pay on the overridden show" do
    let!(:show) { variety_night.tap { |s| s.update!(date_and_time: 3.days.ago) } }
    let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout") }
    let!(:scheme) do
      PayoutScheme.create!(
        organization: org,
        name: "Act Pay",
        rules: {
          "distribution" => {
            "method" => "per_act",
            "act_mode" => "tiers",
            "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ]
          }
        }
      )
    end
    let!(:magic_assignment)  { create(:show_person_role_assignment, show: show, role: magic, assignable: performer) }
    let!(:aerial_assignment) { create(:show_person_role_assignment, show: show, role: aerial, assignable: performer) }

    before { payout.update!(payout_scheme: scheme, calculated_at: nil) }

    it "counts acts straight from the lineup, no ticket numbers needed" do
      expect(show.lineup_act_counts).to eq("Person_#{performer.id}" => 2)

      post manage_calculate_money_show_payout_path(show)

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      payout.reload
      expect(payout.calculated_at).to be_present
      expect(payout.act_counts).to eq("Person_#{performer.id}" => 2)
      expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(50.0)
    end

    it "still asks the role-based sibling for act counts" do
      plain_night.update!(date_and_time: 3.days.ago)
      sibling_payout = ShowPayout.create!(show: plain_night, status: "awaiting_payout", payout_scheme: scheme)
      create(:show_person_role_assignment, show: plain_night, role: magic, assignable: performer)

      post manage_calculate_money_show_payout_path(plain_night)

      expect(response).to redirect_to(manage_money_show_payout_path(plain_night, enter_acts: 1))
      expect(sibling_payout.reload.calculated_at).to be_nil
    end
  end

  describe "saving the override" do
    it "persists casting_mode from the casting settings modal (JSON PATCH)" do
      patch manage_show_path(production, plain_night),
            params: { show: { casting_mode: "act_based" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:see_other)
      expect(plain_night.reload.casting_mode).to eq("act_based")
      expect(plain_night).to be_act_based
    end

    context "when the production has multi-person roles cast for the coming weeks" do
      let!(:dancer) { create(:role, production: production, name: "Dancer", quantity: 3, position: 3) }
      let!(:people) { (1..3).map { |i| create(:person, name: "Dancer #{i}").tap { |p| org.people << p } } }

      before do
        people.each_with_index do |p, i|
          create(:show_person_role_assignment, show: plain_night, role: dancer, assignable: p, position: i + 1)
          create(:show_person_role_assignment, show: variety_night, role: dancer, assignable: p, position: i + 1)
        end
        create(:show_person_role_assignment, show: plain_night, role: magic, assignable: performer)
        ShowCastNotification.create!(show: plain_night, role: dancer, assignable: people[1], notified_at: 1.day.ago, notification_type: :cast)
      end

      it "gives the overriding show its own act lineup with its cast kept, and leaves its siblings and the production's roles alone" do
        patch manage_show_path(production, plain_night),
              params: { show: { casting_mode: "act_based" } }.to_json,
              headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
        expect(response).to have_http_status(:see_other)

        plain_night.reload
        expect(plain_night).to be_act_based
        expect(plain_night).to be_use_custom_roles
        expect(plain_night.custom_roles.map(&:name)).to eq(%w[Magic Variety Aerial Dancer Dancer Dancer])
        expect(plain_night.custom_roles.map(&:quantity)).to all(eq(1))

        cast = plain_night.show_person_role_assignments.reload.includes(:role)
        expect(cast.size).to eq(4)
        expect(cast.map(&:role_id)).to all(be_in(plain_night.custom_roles.map(&:id)))
        expect(cast.group_by(&:role_id).values.map(&:size)).to all(eq(1))
        expect(cast.find { |a| a.assignable == performer }.role.name).to eq("Magic")
        second_dancer_act = cast.find { |a| a.assignable == people[1] }.role
        expect(ShowCastNotification.find_by(show: plain_night, assignable: people[1]).role_id).to eq(second_dancer_act.id)

        # the production's roles and the other show: exactly as they were
        expect(dancer.reload.quantity).to eq(3)
        expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Magic Variety Aerial Dancer])
        expect(variety_night.reload).not_to be_use_custom_roles
        expect(variety_night.show_person_role_assignments.reload.map(&:role_id)).to all(eq(dancer.id))
        expect(variety_night.show_person_role_assignments.map(&:position)).to contain_exactly(1, 2, 3)

        # and the board reads as a numbered lineup
        get manage_casting_show_cast_path(production, plain_night)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-role-name="Act 4 · Dancer"')
        expect(response.body).to include('data-role-name="Act 6 · Dancer"')
      end
    end

    it "clears the override back to inherit when sent an empty string" do
      patch manage_show_path(production, variety_night),
            params: { show: { casting_mode: "" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:see_other)
      expect(variety_night.reload.casting_mode).to be_nil
      expect(variety_night).to be_role_based
    end

    it "offers the casting-style select on the edit screen and saves it" do
      get edit_manage_production_show_path(production, plain_night)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Same as production (Roles)")
      expect(response.body).to include('name="show[casting_mode]"')

      patch manage_show_path(production, plain_night),
            params: { show: { casting_mode: "act_based", event_type: "show", date_and_time: plain_night.date_and_time.iso8601 } }
      expect(response).to have_http_status(:see_other)
      expect(plain_night.reload.casting_mode).to eq("act_based")

      patch manage_show_path(production, plain_night),
            params: { show: { casting_mode: "", event_type: "show", date_and_time: plain_night.date_and_time.iso8601 } }
      expect(plain_night.reload.casting_mode).to be_nil
    end
  end
end

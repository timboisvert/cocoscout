# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CastingSettings", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "opens on the casting source section with a strip to the others" do
    get manage_casting_settings_path(production)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Choose where cast members for this production come from")
    expect(response.body).to include(manage_casting_settings_section_path(production_id: production, section: "roles"))
    expect(response.body).to include(manage_casting_settings_section_path(production_id: production, section: "talent_pool"))
  end

  it "renders the roles section" do
    production.roles.create!(name: "Host")

    get manage_casting_settings_section_path(production_id: production, section: "roles")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Host")
  end

  it "renders the talent pool section, which had no reachable home before" do
    get manage_casting_settings_section_path(production_id: production, section: "talent_pool")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("available for casting in this production")
  end

  it "sends the standalone talent pool URL to its section" do
    get manage_casting_talent_pool_path(production)

    expect(response).to redirect_to(
      manage_casting_settings_section_path(production_id: production, section: "talent_pool")
    )
  end

  it "sends an unknown section back to the default" do
    get manage_casting_settings_section_path(production_id: production, section: "nope")

    expect(response).to redirect_to(manage_casting_settings_path(production))
  end

  describe "casting style" do
    it "offers the roles / acts choice on the source section" do
      get manage_casting_settings_path(production)

      expect(response.body).to include("Casting Style")
      expect(response.body).to include('name="casting_mode"')
      expect(response.body).to include("Existing roles and assignments are kept")
      expect(response.body).to include("Dancer ×5 becomes five Dancer acts, cast kept")
    end

    it "updates the casting mode" do
      patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }

      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(production.reload).to be_act_based
    end

    context "with a role-based lineup already cast for the coming weeks" do
      let!(:show) { create(:show, production: production, date_and_time: 3.days.from_now) }
      let!(:dancer) { production.roles.create!(name: "Dancer", quantity: 3, position: 0) }
      let!(:host)   { production.roles.create!(name: "Host", quantity: 1, position: 1) }
      let!(:people) { (1..3).map { |i| create(:person, name: "Dancer #{i}").tap { |p| org.people << p } } }
      let!(:mc)     { create(:person, name: "The MC").tap { |p| org.people << p } }

      before do
        people.each_with_index { |p, i| create(:show_person_role_assignment, show: show, role: dancer, assignable: p, position: i + 1) }
        create(:show_person_role_assignment, show: show, role: host, assignable: mc, position: 1)
      end

      it "switching to acts splits each multi-person role into one act per person, cast kept" do
        patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }

        expect(response).to redirect_to(manage_casting_settings_path(production))
        lineup = production.roles.production_roles.reload
        expect(lineup.map(&:name)).to eq(%w[Dancer Dancer Dancer Host])
        expect(lineup.map(&:quantity)).to all(eq(1))
        cast = show.show_person_role_assignments.reload.includes(:role)
        expect(cast.size).to eq(4)
        expect(cast.group_by(&:role_id).values.map(&:size)).to all(eq(1))
        people.each { |p| expect(cast.find { |a| a.assignable == p }.role.name).to eq("Dancer") }
        expect(cast.find { |a| a.assignable == mc }.role).to eq(host)
      end

      it "then lists the numbered acts, by name, on the Lineup tab" do
        patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }
        get manage_casting_settings_section_path(production_id: production, section: "roles")

        expect(response).to have_http_status(:ok)
        expect(response.body.scan(/tabular-nums">\s*(\d+)\s*</).flatten).to eq(%w[1 2 3 4])
        expect(response.body.scan(/data-role-name="([^"]+)"/).flatten).to eq(%w[Dancer Dancer Dancer Host])
        expect(response.body).not_to include("slots</span>")
      end

      it "switching back to roles folds the Dancer acts into Dancer ×3 again, everyone in a slot, and role edits work" do
        patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }
        expect(production.roles.production_roles.reload.count).to eq(4)

        patch manage_casting_settings_path(production), params: { production: { casting_mode: "role_based" } }

        expect(production.reload).to be_role_based
        lineup = production.roles.production_roles.reload
        expect(lineup.map { |r| [ r.id, r.name, r.position, r.quantity ] }).to eq([ [ dancer.id, "Dancer", 0, 3 ], [ host.id, "Host", 1, 1 ] ])
        cast = show.show_person_role_assignments.reload.includes(:role)
        expect(cast.size).to eq(4)
        expect(cast.select { |a| a.role_id == dancer.id }.map(&:position)).to contain_exactly(1, 2, 3)
        expect(cast.select { |a| a.role_id == dancer.id }.map(&:assignable)).to match_array(people)

        # a role-based lineup holds one role per name, so renaming and reordering validate again
        patch manage_update_casting_role_path(production, dancer), params: { role: { name: "Dancer", quantity: 3, category: "performing" } }
        expect(response).to redirect_to(manage_casting_settings_section_path(production_id: production, section: "roles"))
        expect(flash[:alert]).to be_nil
        expect(flash[:notice]).to eq("Role was successfully updated")
      end

      it "an act lineup whose repeated names aren't in a row gets suffixed names back in role mode" do
        patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }
        production.roles.production_roles.reload.find_by(position: 1).update_columns(name: "Solo")
        expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Dancer Solo Dancer Host])

        patch manage_casting_settings_path(production), params: { production: { casting_mode: "role_based" } }

        expect(production.roles.production_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Dancer", 1 ], [ "Solo", 1 ], [ "Dancer (2)", 1 ], [ "Host", 1 ] ])
        expect(production.roles.production_roles.reload).to all(be_valid)
      end

      it "does not touch the lineup when the mode is saved unchanged" do
        patch manage_casting_settings_path(production), params: { production: { casting_mode: "role_based" } }

        expect(dancer.reload.quantity).to eq(3)
        expect(production.roles.production_roles.reload.count).to eq(2)
      end
    end

    it "drops an unknown casting mode instead of raising" do
      patch manage_casting_settings_path(production), params: { production: { casting_mode: "sideways" } }

      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(production.reload).to be_role_based
    end

    it "labels the roles section Lineup for an act-based production" do
      production.update!(casting_mode: "act_based")

      get manage_casting_settings_section_path(production_id: production, section: "roles")

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(%r{>\s*Lineup\s*</a>})
      expect(response.body).to include("Add intermission")
      expect(response.body).to include("Add Act")
      expect(response.body).not_to include("Add Role")
    end

    it "numbers acts and shows intermissions as dividers" do
      production.update!(casting_mode: "act_based")
      production.roles.create!(name: "Magic", position: 0)
      production.roles.create!(name: "Intermission", category: "break", position: 1)
      production.roles.create!(name: "Magic", position: 2)

      get manage_casting_settings_section_path(production_id: production, section: "roles")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remove intermission?")
      expect(response.body.scan(/tabular-nums">\s*(\d+)\s*</).flatten).to eq(%w[1 2])
    end

    it "creates an intermission as a break in an act-based production" do
      production.update!(casting_mode: "act_based")

      post manage_create_casting_role_path(production),
           params: { role: { name: "Intermission", category: "break", quantity: "3", restricted: "1" } }

      role = production.roles.find_by(name: "Intermission")
      expect(role.category).to eq("break")
      expect(role.quantity).to eq(1)
      expect(role).not_to be_restricted
    end

    it "turns a break into a performing role in a role-based production" do
      post manage_create_casting_role_path(production),
           params: { role: { name: "Pause", category: "break", quantity: "2" } }

      role = production.roles.find_by(name: "Pause")
      expect(role.category).to eq("performing")
      expect(role.quantity).to eq(2)
    end

    it "keeps the roles section labelled Roles for a role-based production" do
      get manage_casting_settings_section_path(production_id: production, section: "roles")

      expect(response.body).to match(%r{>\s*Roles\s*</a>})
      expect(response.body).to include("Add Role")
      expect(response.body).not_to include("Add intermission")
    end

    it "says under the heading how the production casts" do
      get manage_casting_settings_path(production)
      expect(response.body).to include("#{production.name} casts by roles.")

      production.update!(casting_mode: "act_based")
      get manage_casting_settings_path(production)
      expect(response.body).to include("#{production.name} casts by acts.")
    end
  end

  describe "ways in" do
    let(:settings_path) { manage_casting_settings_path(production) }
    let!(:show) { create(:show, production: production) }

    it "links from the production's casting board, the show board, and the per-show settings modal" do
      get manage_casting_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Casting Settings")
      expect(response.body).to include(settings_path)

      get manage_casting_show_cast_path(production, show)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Production casting settings")
      expect(response.body).to include("Change how the whole production casts (roles or acts, source, lineup) in")
      expect(response.body).to include(settings_path)
    end

    it "lists productions as Roles & Acts on the org casting page, tagged by how each casts" do
      act_production = create(:production, organization: org, name: "Variety Night", casting_mode: "act_based")
      act_production.roles.create!(name: "Magic", position: 0)
      act_production.roles.create!(name: "Intermission", category: "break", position: 1)
      act_production.roles.create!(name: "Clown", position: 2)
      production.roles.create!(name: "Host")

      get manage_casting_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Roles &amp; Acts")
      expect(response.body).not_to include("Roles &amp; Lineups")
      expect(response.body).not_to include("Define roles or a lineup")

      get manage_casting_roles_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Roles &amp; Acts")
      expect(response.body).to include("Choose a production to manage its roles or lineup and casting settings")
      expect(response.body).to include(manage_casting_settings_section_path(production_id: production, section: "roles"))
      expect(response.body).to include(manage_casting_settings_section_path(production_id: act_production, section: "roles"))
      expect(response.body).to match(%r{>\s*Acts\s*</span>})
      expect(response.body).to match(%r{>\s*Roles\s*</span>})
      # The lineup keeps its running order, the intermission as a divider
      expect(response.body).to include("— Intermission —")
      expect(response.body.index("Magic")).to be < response.body.index("— Intermission —")
    end
  end
end

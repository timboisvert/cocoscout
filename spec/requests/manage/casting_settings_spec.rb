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
    end

    it "updates the casting mode" do
      patch manage_casting_settings_path(production), params: { production: { casting_mode: "act_based" } }

      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(production.reload).to be_act_based
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
  end
end

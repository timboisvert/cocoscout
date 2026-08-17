# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Production wizard", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  # Wizard state rides in Rails.cache; the test env cache is a null store.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  before { allow(Rails).to receive(:cache).and_return(memory_cache) }

  def set_up_org(pro: false)
    org = pro ? create(:organization, :pro, owner: user) : create(:organization, owner: user)
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    org.people << person
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path # auto-selects the single org
    org
  end

  describe "free production limit" do
    it "stops a Producer-plan org at the wizard door with the upgrade pitch" do
      org = set_up_org
      create(:production, organization: org)

      get manage_productions_wizard_path

      expect(response).to redirect_to(section_manage_organization_path(org, section: "billing"))
      expect(flash[:notice]).to include("Upgrade to Pro")
    end

    it "lets a Pro org through" do
      set_up_org(pro: true)
      create(:production, organization: Current.organization || Organization.last)

      get manage_productions_wizard_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "genre" do
    it "never prefills the roles step from the genre" do
      set_up_org(pro: true)

      post manage_productions_wizard_save_name_path, params: { name: "Fourth Wall", genre: "improv" }
      get manage_productions_wizard_roles_path

      expect(response.body).not_to include('value="Player"')
      expect(response.body).not_to include('value="Coach"')
    end

    it "stamps the genre on the created production and lands on the manage home" do
      set_up_org(pro: true)

      post manage_productions_wizard_save_name_path, params: { name: "Fourth Wall", genre: "improv" }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      expect(Production.find_by(name: "Fourth Wall").genre).to eq("improv")
      expect(response).to redirect_to(manage_path)
      expect(user.reload.guide_active?(:production_next_steps)).to be(true)
    end

    it "ignores a genre outside the catalog" do
      set_up_org(pro: true)

      post manage_productions_wizard_save_name_path, params: { name: "Mystery", genre: "polka" }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      expect(Production.find_by(name: "Mystery").genre).to be_nil
    end
  end

  describe "casting style" do
    def walk_to_casting_style(name: "Velvet Hour")
      post manage_productions_wizard_save_name_path, params: { name: name }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
    end

    it "follows the casting source with the casting style step" do
      set_up_org(pro: true)
      walk_to_casting_style

      expect(response).to redirect_to(manage_productions_wizard_casting_style_path)
      get manage_productions_wizard_casting_style_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Build a running order")
    end

    it "skips style, roles and pay entirely when there is no casting" do
      set_up_org(pro: true)
      post manage_productions_wizard_save_name_path, params: { name: "Rental" }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "none" }

      expect(response).to redirect_to(manage_productions_wizard_shows_path)
    end

    it "saves act_based and stamps it on the production" do
      set_up_org(pro: true)
      walk_to_casting_style
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "act_based" }
      expect(response).to redirect_to(manage_productions_wizard_roles_path)

      get manage_productions_wizard_roles_path
      expect(response.body).to include("Build your lineup")
      expect(response.body).to include("Add intermission")
      expect(response.body).to include('<option value="break" >Intermission</option>')

      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      post manage_productions_wizard_save_pay_path, params: { pays_performers: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      expect(Production.find_by(name: "Velvet Hour")).to be_act_based
    end

    it "falls back to role_based for an unknown mode" do
      set_up_org(pro: true)
      walk_to_casting_style
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "sideways" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      post manage_productions_wizard_save_pay_path, params: { pays_performers: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      expect(Production.find_by(name: "Velvet Hour")).to be_role_based
    end

    it "parses a break row in act mode and creates it as a break in lineup order" do
      set_up_org(pro: true)
      walk_to_casting_style
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "act_based" }
      post manage_productions_wizard_save_roles_path, params: {
        has_roles: "yes",
        roles: {
          "0" => { name: "Magic", quantity: "4", category: "performing" },
          "1" => { name: "Intermission", category: "break" },
          "2" => { name: "Aerial", category: "performing" }
        }
      }

      get manage_productions_wizard_review_path
      expect(response.body).to include("Lineup")
      expect(response.body).to include("Acts")

      post manage_productions_wizard_save_pay_path, params: { pays_performers: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      production = Production.find_by(name: "Velvet Hour")
      roles = production.roles.order(:position)
      expect(roles.map(&:name)).to eq(%w[Magic Intermission Aerial])
      expect(roles.map(&:category)).to eq(%w[performing break performing])
      # An act is one thing in the running order, whatever quantity was posted.
      expect(roles.map(&:quantity)).to eq([ 1, 1, 1 ])
    end

    it "refuses a break row in role mode" do
      set_up_org(pro: true)
      walk_to_casting_style
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "role_based" }
      post manage_productions_wizard_save_roles_path, params: {
        has_roles: "yes",
        roles: { "0" => { name: "Pause", quantity: "2", category: "break" } }
      }
      post manage_productions_wizard_save_pay_path, params: { pays_performers: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      role = Production.find_by(name: "Velvet Hour").roles.first
      expect(role.category).to eq("performing")
      expect(role.quantity).to eq(2)
    end
  end

  describe "pay step" do
    def walk_to_pay(name: "Velvet Hour")
      post manage_productions_wizard_save_name_path, params: { name: name }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "role_based" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
    end

    it "is skipped for an org without the Money feature" do
      set_up_org(pro: false)
      walk_to_pay

      expect(response).to redirect_to(manage_productions_wizard_shows_path)
      get manage_productions_wizard_pay_path
      expect(response).to redirect_to(manage_productions_wizard_shows_path)
    end

    it "is shown for a Pro org" do
      set_up_org(pro: true)
      walk_to_pay

      expect(response).to redirect_to(manage_productions_wizard_pay_path)
      get manage_productions_wizard_pay_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Will performers be paid for this production?")
    end

    it "points at the presets page when the org has no schemes" do
      set_up_org(pro: true)
      walk_to_pay
      get manage_productions_wizard_pay_path

      expect(response.body).to include("don't have any payout schemes yet")
      expect(response.body).to include(manage_presets_money_payout_schemes_path)
    end

    it "nudges an act-based production toward the Per-Act preset" do
      org = set_up_org(pro: true)
      create(:payout_scheme, organization: org, production: nil, name: "Even split")
      post manage_productions_wizard_save_name_path, params: { name: "Velvet Hour" }
      post manage_productions_wizard_save_logo_path, params: { skip: "true" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "act_based" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      get manage_productions_wizard_pay_path

      expect(response.body).to include("usually pay per act")
      expect(response.body).to include(manage_presets_money_payout_schemes_path(preset: "per_act"))
    end

    it "makes the chosen scheme the new production's default" do
      org = set_up_org(pro: true)
      scheme = create(:payout_scheme, organization: org, production: nil, name: "Door split")
      other_org_scheme = create(:payout_scheme, name: "Not ours")
      walk_to_pay
      get manage_productions_wizard_pay_path
      expect(response.body).to include("Door split")
      expect(response.body).not_to include("Not ours")

      post manage_productions_wizard_save_pay_path, params: { pays_performers: "yes", payout_scheme_id: scheme.id }
      expect(response).to redirect_to(manage_productions_wizard_shows_path)

      get manage_productions_wizard_review_path
      expect(response.body).to include("Door split")

      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      production = Production.find_by(name: "Velvet Hour")
      default = PayoutSchemeDefault.find_by(production_id: production.id)
      expect(default.payout_scheme).to eq(scheme)
      expect(default.effective_from).to eq(Date.current)
      expect(other_org_scheme.payout_scheme_defaults).to be_empty
    end

    it "ignores a scheme from another organization" do
      set_up_org(pro: true)
      other_org_scheme = create(:payout_scheme, name: "Not ours")
      walk_to_pay

      post manage_productions_wizard_save_pay_path, params: { pays_performers: "yes", payout_scheme_id: other_org_scheme.id }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      production = Production.find_by(name: "Velvet Hour")
      expect(PayoutSchemeDefault.where(production_id: production.id)).to be_empty
    end

    it "lets them say yes and set the scheme up later" do
      set_up_org(pro: true)
      walk_to_pay
      post manage_productions_wizard_save_pay_path, params: { pays_performers: "yes", payout_scheme_id: "" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "no" }
      post manage_productions_wizard_create_path

      production = Production.find_by(name: "Velvet Hour")
      expect(production).to be_present
      expect(PayoutSchemeDefault.where(production_id: production.id)).to be_empty
    end
  end
end

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
end

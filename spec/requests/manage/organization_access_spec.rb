# frozen_string_literal: true

require "rails_helper"

# Access by module (plan §9.11): a viewer whose access is a grid sees and
# changes only what the grid gives them.
RSpec.describe "Access by module", type: :request do
  let(:organization) { create(:organization, :pro) }
  let(:user) { create(:user, password: "Password123!") }
  let!(:role) { create(:organization_role, user: user, organization: organization, company_role: "viewer") }

  before do
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  def switch_org
    get manage_path
  end

  context "a bookkeeper" do
    before { role.apply_access!(template: "bookkeeper") }

    it "opens Money" do
      switch_org
      get manage_money_index_path
      expect(response).to have_http_status(:ok)
      get manage_money_financials_path
      expect(response).to have_http_status(:ok)
    end

    it "is kept out of Ticketing" do
      switch_org
      get manage_ticketing_path
      expect(response).to redirect_to(manage_path)
      expect(flash[:notice]).to include("isn't open to you")
    end

    it "can read Money settings but not change them" do
      switch_org
      get manage_money_settings_path
      expect(response).to have_http_status(:ok)
      patch manage_money_settings_notifications_path, params: { organization: { notify: "1" } }
      expect(response).to redirect_to(manage_path)
      expect(flash[:notice]).to include("not change it")
    end
  end

  context "a viewer without a grid" do
    it "keeps today's meaning: no Money" do
      switch_org
      get manage_money_index_path
      expect(response).to redirect_to(manage_path)
      expect(flash[:notice]).to include("managers")
    end
  end

  context "a manager changing someone's access" do
    let(:manager) { create(:user, password: "Password123!") }

    before do
      create(:organization_role, user: manager, organization: organization, company_role: "manager")
      post handle_signin_path, params: { email_address: manager.email_address, password: "Password123!" }
      switch_org
    end

    it "applies a template" do
      patch update_access_manage_team_path(id: user.id), params: { template: "accountant" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(role.reload.access_template).to eq("accountant")
      expect(role.module_grants["books"]).to eq("view")
      expect(JSON.parse(response.body)["label"]).to eq("Accountant")
    end

    it "saves a custom grid" do
      patch update_access_manage_team_path(id: user.id),
            params: { template: "custom", grants: { books: "manage", ticketing: "view", productions: "none" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(role.reload.module_grants).to eq({ "productions" => "view", "books" => "manage", "ticketing" => "view" })
      expect(role.access_template).to eq("custom")
    end

    it "shows the People section with the access chip" do
      role.apply_access!(template: "bookkeeper")
      get section_manage_organization_path(organization, section: "team")
      expect(response.body).to include("Bookkeeper")
      expect(response.body).to include("People")
    end
  end
end

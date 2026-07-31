# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::MoneySettings", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "GET show" do
    it "renders the offline-methods settings section" do
      get manage_money_settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How you pay people outside CocoScout")
      expect(response.body).to include("Zelle").and include("Venmo")
    end

    it "redirects an unknown section to the default" do
      get manage_money_settings_section_path(section: "bogus")
      expect(response).to redirect_to(manage_money_settings_section_path(section: "offline_methods"))
    end
  end

  describe "PATCH update_offline_methods" do
    it "persists the selected methods, dropping unknown values" do
      patch manage_money_settings_offline_methods_path,
        params: { offline_payout_methods: %w[cash venmo bogus] }
      expect(response).to redirect_to(manage_money_settings_section_path(section: "offline_methods"))
      expect(org.reload.enabled_offline_payout_methods).to eq(%w[cash venmo])
    end

    it "clears all methods when none are ticked" do
      org.update!(enabled_offline_payout_methods: %w[cash])
      patch manage_money_settings_offline_methods_path, params: {}
      expect(org.reload.enabled_offline_payout_methods).to eq([])
    end
  end
end

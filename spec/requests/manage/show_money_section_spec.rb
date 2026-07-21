# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Show page money section", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Money Bridge Prod") }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  context "when the org is on a paid (Pro) plan" do
    let!(:org) { create(:organization, :pro, owner: owner) }

    it "shows a Money box with a Pro badge and links to financials, payouts, and advances" do
      get manage_show_path(production, show)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(">Money<").and include(">Pro<")
      expect(response.body).to include(manage_money_show_financials_path(show))
      expect(response.body).to include(manage_money_show_payout_path(show))
    end
  end

  context "when the org is not on a paid plan" do
    let!(:org) { create(:organization, owner: owner) }

    it "does not show the Money box" do
      get manage_show_path(production, show)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(manage_money_show_financials_path(show))
    end
  end
end

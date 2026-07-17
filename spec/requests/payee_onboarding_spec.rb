# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PayeeOnboarding", type: :request do
  let(:person) { create(:person, name: "Guest Gigi", email: "gigi@example.com") }
  let(:token) { PayeeOnboardingToken.generate(person) }

  describe "GET /pay/setup/:token" do
    it "renders the connect-your-bank page for a valid token (no login)" do
      get payee_onboarding_path(token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Guest Gigi").and include("Connect your bank")
    end

    it "shows the all-set state once the payee can receive payouts" do
      person.update!(stripe_account_id: "acct_x", payouts_enabled: true)
      get payee_onboarding_path(token: token)
      expect(response.body).to include("You're all set")
    end

    it "returns 404 with an expired-link page for a bad token" do
      get payee_onboarding_path(token: "garbage")
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("expired")
    end
  end

  describe "POST /pay/setup/:token/connect" do
    it "redirects to the Stripe onboarding URL" do
      allow_any_instance_of(StripeConnectService).to receive(:onboarding_link)
        .and_return("https://connect.stripe.com/setup/abc")
      post payee_onboarding_connect_path(token: token)
      expect(response).to redirect_to("https://connect.stripe.com/setup/abc")
    end
  end

  describe "GET /pay/setup/:token/return" do
    it "syncs the account and re-renders the status page" do
      person.update!(stripe_account_id: "acct_x")
      expect_any_instance_of(StripeConnectService).to receive(:sync_account).and_return(person)
      get payee_onboarding_return_path(token: token)
      expect(response).to have_http_status(:ok)
    end
  end
end

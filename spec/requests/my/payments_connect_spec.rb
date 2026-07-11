# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Payments bank connect", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "shows the connect-your-bank action on the setup page" do
    get my_payments_setup_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bank account")
    expect(response.body).to include("Connect your bank")
  end

  it "redirects to Stripe hosted onboarding when connecting" do
    allow_any_instance_of(StripeConnectService).to receive(:onboarding_link)
      .and_return("https://connect.stripe.com/setup/abc")

    post my_payments_connect_bank_path
    expect(response).to redirect_to("https://connect.stripe.com/setup/abc")
  end

  it "syncs the account and returns to setup after onboarding" do
    person.update!(stripe_account_id: "acct_1")
    allow_any_instance_of(StripeConnectService).to receive(:sync_account) do
      person.update!(payouts_enabled: true, stripe_account_status: "enabled")
      person
    end

    get my_payments_connect_return_path
    expect(response).to redirect_to(my_payments_setup_path)
    expect(person.reload.can_receive_payouts?).to be(true)
  end

  it "surfaces a friendly error if onboarding can't start" do
    allow_any_instance_of(StripeConnectService).to receive(:onboarding_link)
      .and_raise(StripeConnectService::Error, "Stripe down")

    post my_payments_connect_bank_path
    expect(response).to redirect_to(my_payments_setup_path)
    follow_redirect!
    expect(response.body).to include("Couldn&#39;t start bank setup").or include("Couldn't start bank setup")
  end
end

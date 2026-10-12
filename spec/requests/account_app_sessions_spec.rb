# frozen_string_literal: true

require "rails_helper"

# The Account page lists the phones signed in to the app, each with Sign out
# (Tim, 2026-10-12).
RSpec.describe "Signing a phone out from the Account page", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists the phone and signs it out" do
    session, = AppSession.start!(user, device_name: "Tim's iPhone")

    get account_path
    expect(response.body).to include("Signed in on the app: Tim&#39;s iPhone")

    delete sign_out_app_account_path(session)
    expect(response).to redirect_to(account_path)
    expect(flash[:notice]).to eq("Tim's iPhone is signed out of the app.")
    expect(user.app_sessions).to be_empty
  end

  it "never signs out someone else's phone" do
    theirs, = AppSession.start!(create(:user))

    delete sign_out_app_account_path(theirs)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).to be_persisted
  end
end

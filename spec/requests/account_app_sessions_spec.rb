# frozen_string_literal: true

require "rails_helper"

# Where you're signed in, on the Account page (Tim, 2026-10-12): every other
# browser and app phone (the iOS app signs in through the web), each with
# Sign out, and a new password signs them all out.
RSpec.describe "Signing out other devices from the Account page", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let(:app_agent) { "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Turbo Native iOS" }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists the app phone signed in through the web and signs it out, keeping this one" do
    phone = user.sessions.create!(user_agent: app_agent, ip_address: "10.0.0.2")
    here = user.sessions.where.not(id: phone.id).sole

    get account_path
    expect(response.body).to include("Where you're signed in", "and 1 other place", "CocoScout app on iPhone")

    delete sign_out_session_account_path(phone)
    expect(flash[:notice]).to eq("CocoScout app on iPhone is signed out.")
    expect(user.sessions.reload).to eq([ here ])
  end

  it "signs out everywhere else, app sign-ins included" do
    user.sessions.create!(user_agent: app_agent)
    AppSession.start!(user, device_name: "Tim's iPhone")

    get account_path
    expect(response.body).to include("Tim&#39;s iPhone", "and 2 other places")

    delete sign_out_elsewhere_account_path
    expect(user.sessions.count).to eq(1)
    expect(user.app_sessions).to be_empty
  end

  it "signs every other device out when the password is reset" do
    phone = user.sessions.create!(user_agent: app_agent)
    app_session, = AppSession.start!(user)

    post handle_reset_path(token: user.generate_token_for(:password_reset)), params: { password: "NewPassword456!" }
    expect { phone.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect { app_session.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(user.sessions.count).to eq(1) # the one the reset just signed in
  end

  it "never signs out someone else's devices" do
    theirs = create(:user).sessions.create!(user_agent: app_agent)
    their_app, = AppSession.start!(create(:user))

    delete sign_out_session_account_path(theirs)
    expect(response).to have_http_status(:not_found)
    delete sign_out_app_account_path(their_app)
    expect(response).to have_http_status(:not_found)
    expect([ theirs.reload, their_app.reload ]).to all(be_persisted)
  end
end

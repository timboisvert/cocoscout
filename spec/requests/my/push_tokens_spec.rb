# frozen_string_literal: true

require "rails_helper"

# The iOS app's push notifications for a phone, filed under the web sign-in
# the app runs on (bridge/push_controller.js).
RSpec.describe "Push notifications on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let(:token) { "ab" * 32 }

  def sign_in(as = user)
    post handle_signin_path, params: { email_address: as.email_address, password: password }
  end

  it "files the phone under this sign-in, and signing out stops its notifications" do
    sign_in
    post my_push_token_path, params: { token: token.upcase, environment: "sandbox" }, as: :json
    expect(response).to have_http_status(:no_content)

    phone = DeviceToken.find_by!(token: token)
    expect(phone).to have_attributes(user: user, platform: "ios", apns_environment: "sandbox", session: user.sessions.last)
    expect(user.push_enabled?).to be(true)

    get signout_path
    expect(DeviceToken.exists?(phone.id)).to be(false)
  end

  it "ends a phone's notifications when Account signs that phone out" do
    sign_in
    post my_push_token_path, params: { token: token }, as: :json
    phone = DeviceToken.find_by!(token: token)

    phone.session.destroy
    expect(DeviceToken.exists?(phone.id)).to be(false)
  end

  it "moves a phone to whoever signs in on it next" do
    other = create(:user, password: password)
    create(:device_token, user: other, token: token)

    sign_in
    post my_push_token_path, params: { token: token }, as: :json
    expect(DeviceToken.where(token: token).pluck(:user_id)).to eq([ user.id ])
  end

  it "forgets the phone once notifications are turned off, and counts a quiet phone as off" do
    sign_in
    post my_push_token_path, params: { token: token }, as: :json
    DeviceToken.find_by!(token: token).update_columns(updated_at: 31.days.ago)
    expect(user.push_enabled?).to be(false)

    delete my_push_token_path, params: { token: token }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(DeviceToken.exists?(token: token)).to be(false)
  end

  it "turns away anything that isn't a phone's token, and anyone signed out" do
    post my_push_token_path, params: { token: token }, as: :json
    expect(DeviceToken.count).to eq(0)

    sign_in
    post my_push_token_path, params: { token: "not-a-token" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(DeviceToken.count).to eq(0)
  end
end

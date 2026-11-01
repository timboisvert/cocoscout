# frozen_string_literal: true

require "rails_helper"

# Being sent to sign in remembers where you were, in the session cookie —
# which holds 4KB. A page with a long address (a GET form's worth of fields)
# comes back without its query rather than overflowing the cookie into a 500.
RSpec.describe "Signing in returns you to where you were", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }

  it "comes back to the page with its query when the address is short" do
    get "/manage/contracts?status=active"
    expect(response).to redirect_to(signin_path)

    post handle_signin_path, params: { email_address: user.email_address, password: password }

    expect(response).to redirect_to("http://www.example.com/manage/contracts?status=active")
  end

  it "comes back to the page alone when its address is too long for the cookie" do
    long = (1..40).map { |i| "dates[#{i}][starts_at]=2026-10-01T11:00&dates[#{i}][duration]=2&dates[#{i}][action]=keep" }.join("&")
    get "/manage/contracts/1/amend/dates/review?#{long}"
    expect(response).to redirect_to(signin_path)

    post handle_signin_path, params: { email_address: user.email_address, password: password }

    expect(response).to redirect_to("http://www.example.com/manage/contracts/1/amend/dates/review")
  end
end

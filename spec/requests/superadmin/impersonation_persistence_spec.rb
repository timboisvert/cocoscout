# frozen_string_literal: true

require "rails_helper"

# The impersonation banner used to be driven entirely by browser-session
# cookies (the Rails session + a signed :impersonator_user_id cookie) while the
# login itself rides the *permanent* signed :session_id cookie. Mobile browsers
# drop session cookies well before the permanent one — force-quit, tab
# eviction, memory pressure — so the superadmin stayed signed in as the
# impersonated person with no banner and no way to stop.
#
# These specs pin the real invariant: the banner and its Stop button must
# survive losing every browser-session cookie, and Stop must still restore the
# original user afterwards.
RSpec.describe "Impersonation persistence", type: :request do
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:target) { create(:user, password: "Password123!") }

  # Everything a mobile browser throws away when it decides the browsing
  # session is over, leaving only the permanent :session_id login cookie.
  def drop_browser_session_cookies!
    cookies.delete(Rails.application.config.session_options[:key])
    cookies.delete("impersonator_user_id")
  end

  before do
    post handle_signin_path, params: { email_address: superadmin.email_address, password: "Password123!" }
    post impersonate_user_path, params: { email: target.email_address }
  end

  it "records the impersonator on the session row, not just in cookies" do
    expect(target.sessions.last.impersonator_user_id).to eq(superadmin.id)
  end

  it "still renders the banner after the browser drops its session cookies" do
    drop_browser_session_cookies!

    get my_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Impersonating")
    expect(response.body).to include(stop_impersonating_user_path)
  end

  it "still restores the original user after the browser drops its session cookies" do
    drop_browser_session_cookies!

    post stop_impersonating_user_path

    expect(superadmin.sessions.reload).to be_present
    expect(target.sessions.reload).to be_empty
  end

  it "clears the impersonator when impersonation stops" do
    post stop_impersonating_user_path

    expect(superadmin.sessions.reload.map(&:impersonator_user_id)).to all(be_nil)

    get my_dashboard_path
    expect(response.body).not_to include(stop_impersonating_user_path)
  end
end

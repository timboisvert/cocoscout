# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CoursePayoutSettings", type: :request do
  let(:password) { "Password123!" }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "renders for a non-Pro org (courses payouts are not gated behind Pro)" do
    org = create(:organization) # not :pro
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_payout_settings_path

    expect(response).to have_http_status(:ok)
    # The real settings page rendered (not the Pro paywall template).
    expect(response.body).to include("Getting paid for your courses")
    expect(response.body).to include("Connect your bank")
  end

  it "shows a connected state once the org can receive payouts" do
    org = create(:organization)
    org.update!(stripe_account_id: "acct_test", payouts_enabled: true)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_payout_settings_path

    expect(response.body).to include("Connected")
    expect(response.body).to include("is set up to get paid")
  end
end

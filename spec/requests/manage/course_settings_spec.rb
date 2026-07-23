# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseSettings", type: :request do
  let(:password) { "Password123!" }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "renders for a non-Pro org (courses payouts are not gated behind Pro)" do
    org = create(:organization) # not :pro
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_settings_path

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

    get manage_course_settings_path

    expect(response.body).to include("Connected")
    expect(response.body).to include("is set up to get paid")
  end

  it "hides the section strip while there's only one section" do
    org = create(:organization)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_settings_path

    expect(response.body).to include("Course Settings")
    expect(response.body).not_to include(%(aria-label="Settings sections"))
  end

  it "still answers the old payouts-settings URL Stripe was given" do
    org = create(:organization)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get "/manage/courses/payouts/settings"

    expect(response).to redirect_to("/manage/courses/settings")
  end
end

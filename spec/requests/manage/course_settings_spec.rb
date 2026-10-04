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

  it "shows the section strip now that Payments has Taxes beside it" do
    org = create(:organization)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_settings_path

    expect(response.body).to include("Course Settings", %(aria-label="Settings sections"), "Payments", "Taxes")
  end

  it "still answers the old payouts-settings URL Stripe was given" do
    org = create(:organization)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get "/manage/courses/payouts/settings"

    expect(response).to redirect_to("/manage/courses/settings")
  end

  it "has a Taxes tab with the one course-tax setting, for a non-Pro org too" do
    org = create(:organization)
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)

    get manage_course_settings_section_path(section: "taxes")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Taxes", "If you charge tax on courses", "$150 course")

    patch manage_course_settings_tax_path, params: { tax: { name: "Sales tax", percent: "10.25", mode: "added" } }
    expect(response).to redirect_to(manage_course_settings_section_path(section: "taxes"))
    expect(TicketTaxSetting.current(org, kind: "courses").percent).to eq("10.25")
    expect(TicketTaxSetting.current(org).set?).to be(false)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Reports", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the reports index" do
    get manage_reports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reports")
  end

  it "renders each built report without error" do
    [
      manage_report_revenue_by_production_path,
      manage_report_revenue_over_time_path,
      manage_report_events_summary_path,
      manage_report_cast_participation_path,
      manage_report_payouts_summary_path,
      manage_report_course_revenue_path
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to render"
    end
  end

  it "downloads each report as a CSV spreadsheet" do
    [
      manage_report_revenue_by_production_path(format: :csv),
      manage_report_revenue_over_time_path(format: :csv),
      manage_report_events_summary_path(format: :csv),
      manage_report_cast_participation_path(format: :csv),
      manage_report_payouts_summary_path(format: :csv),
      manage_report_course_revenue_path(format: :csv)
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to download"
      expect(response.media_type).to eq("text/csv"), "expected #{path} to be CSV"
      expect(response.headers["Content-Disposition"]).to include(".csv")
    end
  end

  it "presents Payouts as its own section and drops the coming-soon reports" do
    get manage_reports_path
    expect(response.body).to include("Payouts")
    expect(response.body).not_to include("Coming soon")
    expect(response.body).not_to include("Availability Response Rates")
  end

  it "gates reports behind the Pro plan" do
    free_owner = create(:user, password: password)
    free_org = create(:organization, owner: free_owner)
    create(:organization_role, :manager, user: free_owner, organization: free_org)
    post handle_signin_path, params: { email_address: free_owner.email_address, password: password }

    get manage_reports_path
    expect(response).to have_http_status(:payment_required)
    expect(response.body).to include("Reports")
  end
end

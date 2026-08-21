# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferingPayouts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 4000) }
  let!(:registration) { create(:course_registration, course_offering: offering, amount_cents: 4000, status: "confirmed") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def make_payable(record)
    record.update!(stripe_account_id: "acct_#{record.class.name.downcase}_#{record.id}", payouts_enabled: true)
    record
  end

  it "renders the run-based payouts page without any mark-paid/venmo cruft" do
    make_payable(org)
    get manage_course_offering_payout_path(offering)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payouts")
    expect(response.body).to include("Add to payout run")
    expect(response.body).not_to include("Mark Paid")
    expect(response.body).not_to include("Venmo")
  end

  it "adds the org's remainder to the performer payout run (the one rail)" do
    make_payable(org)
    get manage_course_offering_payout_path(offering) # sets up the payout, as the UI does

    expect {
      post manage_course_offering_payout_add_to_run_path(offering)
    }.to change { PayoutBatch.of_kind("performer").count }.by(1)

    run = PayoutBatch.of_kind("performer").last
    expect(run.items.find_by(payee: org)).to be_present
    expect(response).to redirect_to(manage_course_offering_payout_path(offering))
  end

  it "sets up the payout on first visit instead of bouncing with an error" do
    expect(offering.course_offering_payout).to be_nil

    expect {
      get manage_course_offering_payout_path(offering)
    }.to change { offering.reload.course_offering_payout.present? }.from(false).to(true)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Revenue Summary")
    expect(response.body).not_to include("No payout has been calculated yet")
  end

  it "reuses the existing payout on later visits" do
    get manage_course_offering_payout_path(offering)
    payout_id = offering.reload.course_offering_payout.id

    expect {
      get manage_course_offering_payout_path(offering)
    }.not_to change(CourseOfferingPayout, :count)

    expect(offering.reload.course_offering_payout.id).to eq(payout_id)
  end
end

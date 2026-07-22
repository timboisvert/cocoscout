# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CoursePayoutRuns", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def make_payable(record)
    record.update!(stripe_account_id: "acct_#{record.class.name.downcase}_#{record.id}", payouts_enabled: true)
    record
  end

  def build_run
    make_payable(org)
    payout = offering.create_course_offering_payout!(status: "calculated", total_revenue_cents: 3800,
                                                     platform_fee_cents: 0, net_revenue_cents: 3800, total_payout_cents: 0)
    CoursePayoutRunService.add_to_run!(payout).batch
  end

  it "shows an empty state when there's no course run" do
    get manage_course_payout_run_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No course payouts to send")
  end

  it "lists the run's recipients and a pay action, non-Pro" do
    build_run # org is not :pro
    get manage_course_payout_run_path

    expect(response).to have_http_status(:ok)
    # The real page rendered (not the Pro paywall template).
    expect(response.body).to include("Recipients")
    expect(response.body).to include("Pay everyone now")
    expect(response.body).not_to include("feature_paywall")
  end

  it "pays the run and transfers to each recipient" do
    batch = build_run
    allow(Stripe::Transfer).to receive(:create) { |args| double(id: "tr_#{args[:destination]}") }
    allow(Stripe).to receive(:api_key).and_return("sk_test_x")

    post manage_course_payout_run_pay_path

    expect(batch.reload.status).to eq("completed")
    expect(batch.items.all?(&:paid?)).to be(true)
    expect(response).to redirect_to(manage_course_payout_run_path)
  end
end

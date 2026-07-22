# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseMoney", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the money statement with payments and refunds, non-Pro" do
    create(:course_registration, course_offering: offering, amount_cents: 4000,
                                 cocoscout_fee_cents: 200, status: "confirmed",
                                 stripe_payment_intent_id: "pi_abc")
    create(:course_registration, course_offering: offering, amount_cents: 4000,
                                 status: "refunded", stripe_refund_id: "re_xyz", refunded_at: Time.current)

    get manage_course_money_path(offering)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Money summary")
    expect(response.body).to include("Payments in")
    expect(response.body).to include("pi_abc")   # payment traceable to Stripe
    expect(response.body).to include("Refunds out")
    expect(response.body).to include("re_xyz")    # refund traceable to Stripe
    expect(response.body).not_to include("feature_paywall")
  end
end

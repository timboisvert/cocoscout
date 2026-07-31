# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferingPayouts offline mark-paid", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production) }
  let!(:payout) do
    offering.create_course_offering_payout!(status: "calculated", total_revenue_cents: 5000,
                                            platform_fee_cents: 0, net_revenue_cents: 5000, total_payout_cents: 3000)
  end
  let!(:person) { create(:person) }
  let!(:line) do
    payout.line_items.create!(payee: person, amount_cents: 3000, label: "Janelle",
                              calculation_details: { type: "instructor" })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "records a line item paid offline and settles the payout" do
    post manage_course_offering_payout_mark_line_item_paid_path(offering, line), params: { method: "zelle", notes: "ref 1" }

    expect(line.reload.paid?).to be(true)
    expect(line.payment_method).to eq("zelle")
    expect(payout.reload.status).to eq("paid")
  end
end

# frozen_string_literal: true

require "rails_helper"

# Refunding a course's registrations has to dissolve what anyone was owed from
# it — the instructor's cut was a share of money that's now been handed back —
# and every money page has to say so.
RSpec.describe "Manage::CourseOfferings refunds", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 5000) }
  let(:instructor) { create(:person, name: "Janelle Kloth") }
  let!(:registrations) do
    3.times.map do
      create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500,
                                   status: "confirmed", stripe_payment_intent_id: nil)
    end
  end

  before do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 20)
    CoursePayoutCalculator.new(offering).calculate!
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def refund!(registration)
    post manage_course_offering_refund_registration_path(offering, registration_id: registration.id)
    expect(response).to redirect_to(manage_course_offering_path(offering))
  end

  it "dissolves the instructor payout once everyone is refunded" do
    registrations.each { |r| refund!(r) }

    payout = offering.course_offering_payout.reload
    expect(payout.line_items).to be_empty
    expect(payout.total_payout_cents).to eq(0)
    expect(registrations.map { |r| r.reload.status }).to all(eq("refunded"))
  end

  it "shows the course as refunded with nothing owed, never a negative gross" do
    registrations.each { |r| refund!(r) }

    get manage_course_offering_path(offering)

    expect(response.body).to include("$0.00")
    expect(response.body).not_to include("-$150.00")
    expect(response.body).not_to include("Owed to others")
    expect(response.body).not_to include("Awaiting Payment")
    expect(response.body).to include("Refunded — nothing to pay out")
  end

  it "shows no direct costs or instructor payout on Money → Financials" do
    registrations.each { |r| refund!(r) }

    get manage_money_production_financials_path(production)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("$27.00")
    expect(response.body).not_to include("-$27.00")
    expect(response.body).not_to include("Janelle Kloth")
  end

  it "rescales, rather than dissolves, on a partial refund" do
    refund!(registrations.first)

    payout = offering.course_offering_payout.reload
    expect(payout.line_items.sum(:amount_cents)).to eq(1800) # 20% of the $90 still kept

    get manage_course_offering_path(offering)
    expect(response.body).to include("$100.00") # gross now
    expect(response.body).to include("$18.00")  # owed to others
  end
end

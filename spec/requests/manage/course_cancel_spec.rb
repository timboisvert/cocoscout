# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferings cancel course", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 5000, status: "open") }

  before do
    allow(Stripe).to receive(:api_key).and_return("sk_test_x")
    allow(Stripe::Refund).to receive(:create) { |args| double(id: "re_#{args[:payment_intent]}") }
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "offers Cancel Course on a live course, with the counts it will act on" do
    2.times { |i| create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed", stripe_payment_intent_id: "pi_#{i}") }
    create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: 3.days.from_now)

    get manage_course_offering_path(offering)

    expect(response.body).to include("Cancel Course")
    expect(response.body).to include("2 paid registrations")
    expect(response.body).to include("1 session")
    expect(response.body).to include("notify_registrants")
  end

  it "marks the course cancelled at once and hands the refunds to a job" do
    create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed", stripe_payment_intent_id: "pi_1")

    expect {
      post manage_cancel_course_offering_path(offering), params: { notify_registrants: "1" }
    }.to have_enqueued_job(CourseCancellationJob).with(offering.id)

    expect(response).to redirect_to(manage_course_offering_path(offering))
    expect(offering.reload).to have_attributes(status: "cancelled", cancelled_by_user: owner, cancellation_notify_registrants: true)
    expect(offering.cancelled_at).to be_present
    expect(offering.accepting_registrations?).to be false
    expect(flash[:notice]).to include("Refunds are being sent to 1 registrant")
  end

  it "remembers a choice not to notify" do
    post manage_cancel_course_offering_path(offering), params: { notify_registrants: "0" }
    expect(offering.reload.cancellation_notify_registrants).to be false
  end

  it "shows a Cancelled badge afterwards and no lifecycle buttons" do
    post manage_cancel_course_offering_path(offering)
    perform_enqueued_jobs

    get manage_course_offering_path(offering)

    expect(response.body).to include("Cancelled")
    expect(response.body).not_to include("Close Registration")
    expect(response.body).not_to include("Open Registration")
    expect(response.body).not_to include("Cancel Course")
  end

  it "keeps a refund Stripe refused visible with a retry, and the retry clears it" do
    reg = create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed", stripe_payment_intent_id: "pi_bad")
    allow(Stripe::Refund).to receive(:create).and_raise(Stripe::StripeError.new("try later"))

    post manage_cancel_course_offering_path(offering)
    perform_enqueued_jobs
    expect(reg.reload).to be_confirmed

    get manage_course_offering_path(offering)
    expect(response.body).to include("1 registrant still to refund")
    expect(response.body).to include("Retry refunds")

    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_ok"))
    post manage_retry_cancellation_course_offering_path(offering)
    perform_enqueued_jobs
    expect(reg.reload).to be_refunded

    get manage_course_offering_path(offering)
    expect(response.body).not_to include("still to refund")
  end

  it "refuses to cancel a contract-backed course here" do
    contract = create(:contract, :active, organization: org, production: production)
    offering.update!(contract: contract)

    post manage_cancel_course_offering_path(offering)

    expect(offering.reload).to be_open
    expect(flash[:alert]).to include("Cancel the contract instead")
  end

  it "refuses to cancel twice" do
    post manage_cancel_course_offering_path(offering)
    expect {
      post manage_cancel_course_offering_path(offering)
    }.not_to have_enqueued_job(CourseCancellationJob)
    expect(flash[:alert]).to include("already cancelled")
  end

  it "closes the public door: the course is hidden and the registration page says why" do
    offering.update!(listed_in_directory: true)
    post manage_cancel_course_offering_path(offering)

    get my_course_inactive_path(code: offering.short_code)
    expect(response.body).to include("This Course Has Been Cancelled")
  end
end

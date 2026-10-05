# frozen_string_literal: true

require "rails_helper"

# A course registration starts as a ten-minute hold on a spot and is
# confirmed once paid: by the done page or the webhook, whichever is first.
RSpec.describe "CourseCheckout and CourseCheckoutSettlement" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 10_000, capacity: 2) }
  let(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }

  before do
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "8", mode: "added")
    allow(Stripe::Refund).to receive(:create)
  end

  it "holds a spot for ten minutes, priced with its tax, and reuses the hold on a second try" do
    registration = CourseCheckout.start!(offering: offering, user: user)
    expect(registration).to be_pending
    expect(registration.token).to be_present
    expect(registration.amount_cents).to eq(10_000)
    expect(registration.tax_cents).to eq(800)
    expect(registration.total_cents).to eq(10_800)
    expect(registration.cocoscout_fee_cents).to eq(1_000)
    expect(registration.expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    expect(offering.reload.spots_remaining).to eq(1)

    expect(CourseCheckout.start!(offering: offering, user: user)).to eq(registration)
    expect(CourseRegistration.count).to eq(1)
  end

  it "counts live holds against capacity, frees a lapsed one, and refuses a full course" do
    first = CourseCheckout.start!(offering: offering, user: user)
    other = create(:user)
    create(:person, user: other, email: other.email_address)
    CourseCheckout.start!(offering: offering, user: other)
    third = create(:user)
    create(:person, user: third, email: third.email_address)
    expect { CourseCheckout.start!(offering: offering, user: third) }.to raise_error(CourseCheckout::Error, /full/)

    first.update!(expires_at: 1.minute.ago)
    expect(offering.reload.spots_remaining).to eq(1)
    ExpireTicketHoldsJob.perform_now
    expect(first.reload).to be_expired
    expect(CourseCheckout.start!(offering: offering, user: third)).to be_pending
  end

  it "refuses someone already registered" do
    create(:course_registration, course_offering: offering, person: person, status: "confirmed")
    expect { CourseCheckout.start!(offering: offering, user: user) }.to raise_error(CourseCheckout::Error, /already registered/)
  end

  it "settles once, records the tax and queues the confirmation, however many times it's asked" do
    registration = CourseCheckout.start!(offering: offering, user: user)
    allow(registration).to receive(:record_stripe_fee!)
    CourseCheckoutSettlement.settle!(registration, payment_intent_id: "pi_1", charge_id: "ch_1")
    CourseCheckoutSettlement.settle!(registration, payment_intent_id: "pi_1", charge_id: "ch_1")
    registration.reload
    expect(registration).to be_confirmed
    expect(registration.paid_at).to be_present
    expect(registration.expires_at).to be_nil
    expect(registration.stripe_payment_intent_id).to eq("pi_1")
    expect(registration.tax_lines.sum(:tax_cents)).to eq(800)
    expect(enqueued_jobs.count { |j| j["job_class"] == "CourseRegistrationConfirmationJob" }).to eq(1)
    expect(OrgCashEntry.find_by(source: registration, entry_type: "course_registration").amount_cents).to eq(10_800 - 1_000)
  end

  it "honors a payment that lands after the hold ran out while the spot is still there, and refunds one that doesn't" do
    registration = CourseCheckout.start!(offering: offering, user: user)
    registration.update!(status: "expired")
    allow(registration).to receive(:record_stripe_fee!)
    CourseCheckoutSettlement.settle!(registration, payment_intent_id: "pi_late")
    expect(registration.reload).to be_confirmed

    late = create(:user)
    create(:person, user: late, email: late.email_address)
    hold = CourseCheckout.start!(offering: offering, user: late)
    hold.update!(expires_at: 1.minute.ago)
    filler = create(:user)
    create(:person, user: filler, email: filler.email_address)
    CourseCheckoutSettlement.settle!(CourseCheckout.start!(offering: offering, user: filler))
    expect(offering.reload.confirmed_registrations_count).to eq(2)

    CourseCheckoutSettlement.settle!(hold, payment_intent_id: "pi_too_late")
    expect(hold.reload).to be_refunded
    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: "pi_too_late" }, anything)
  end

  it "makes a free course free" do
    offering.update!(price_cents: 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "0", mode: "added")
    registration = CourseCheckout.start!(offering: offering, user: user)
    expect(registration.total_cents).to eq(0)
    CourseCheckoutSettlement.settle!(registration)
    expect(registration.reload).to be_confirmed
    expect(OrgCashEntry.where(source: registration)).to be_empty
  end
end

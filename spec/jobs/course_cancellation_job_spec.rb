# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCancellationJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 5000, status: "cancelled", cancelled_at: Time.current) }
  let(:instructor) { create(:person) }

  before do
    allow(Stripe).to receive(:api_key).and_return("sk_test_x")
    allow(Stripe::Refund).to receive(:create) { |args| double(id: "re_#{args[:payment_intent]}") }
    offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 20)
  end

  def paid_registration(pi:)
    create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500,
                                 status: "confirmed", stripe_payment_intent_id: pi, person: create(:person, email: "#{pi}@example.com"))
  end

  it "refunds every paid registrant, removes pending ones, cancels sessions, and dissolves the payout" do
    paid = [ paid_registration(pi: "pi_a"), paid_registration(pi: "pi_b") ]
    pending = create(:course_registration, course_offering: offering, amount_cents: 5000, status: "pending")
    session = create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: 3.days.from_now)
    CoursePayoutCalculator.new(offering).calculate!
    expect(offering.course_offering_payout.line_items.sum(:amount_cents)).to eq(1800)

    perform_enqueued_jobs { described_class.perform_later(offering.id) }

    expect(paid.map { |r| r.reload.status }).to all(eq("refunded"))
    expect(pending.reload).to be_cancelled
    expect(session.reload).to be_canceled
    expect(offering.course_offering_payout.reload.line_items).to be_empty
    expect(offering.course_offering_payout.total_payout_cents).to eq(0)
  end

  it "tells each affected registrant, with their refund amount, from the seeded template" do
    paid_registration(pi: "pi_a")
    create(:course_registration, course_offering: offering, amount_cents: 5000, status: "pending",
                                 person: create(:person, email: "pending@example.com"))

    expect {
      perform_enqueued_jobs { described_class.perform_later(offering.id) }
    }.to change { ActionMailer::Base.deliveries.size }.by(2)

    refunded_mail = ActionMailer::Base.deliveries.find { |m| m.to.include?("pi_a@example.com") }
    expect(refunded_mail.subject).to include("has been cancelled")
    expect(refunded_mail.body.encoded).to include("$50")
  end

  it "says nothing when the manager chose not to notify" do
    offering.update!(cancellation_notify_registrants: false)
    paid_registration(pi: "pi_a")

    expect {
      perform_enqueued_jobs { described_class.perform_later(offering.id) }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "leaves a registration Stripe refused as confirmed, and refunds it on a retry" do
    bad = paid_registration(pi: "pi_bad")
    good = paid_registration(pi: "pi_good")
    allow(Stripe::Refund).to receive(:create) do |args|
      raise Stripe::StripeError, "try later" if args[:payment_intent] == "pi_bad"
      double(id: "re_ok")
    end

    perform_enqueued_jobs { described_class.perform_later(offering.id) }
    expect(good.reload).to be_refunded
    expect(bad.reload).to be_confirmed

    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_retry"))
    perform_enqueued_jobs { described_class.perform_later(offering.id) }
    expect(bad.reload).to be_refunded
    # The good one wasn't refunded twice.
    expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_good")).once
  end

  it "does nothing for a course that isn't cancelled" do
    offering.update!(status: "open", cancelled_at: nil)
    reg = paid_registration(pi: "pi_a")

    perform_enqueued_jobs { described_class.perform_later(offering.id) }

    expect(reg.reload).to be_confirmed
    expect(Stripe::Refund).not_to have_received(:create)
  end
end

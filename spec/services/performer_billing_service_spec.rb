# frozen_string_literal: true

require "rails_helper"

RSpec.describe PerformerBillingService do
  let(:org) { create(:organization, :pro) }
  let(:this_month) { Date.current }

  it "counts performers paid this month (via activations) at $3 each" do
    paid = create(:person, name: "Paid Paige")
    create(:person, name: "Unpaid Uma") # never paid this month

    PerformerActivation.record!(organization: org, person: paid, month: this_month)

    svc = described_class.new(org)
    expect(svc.active_count).to eq(1)
    expect(svc.active_performer_cents).to eq(300)
    expect(svc.monthly_estimate_cents).to eq(300)
    expect(svc.active_performers).to contain_exactly(paid)
  end

  it "counts each performer once no matter how many payouts that month" do
    paige = create(:person, name: "Paid Paige")
    PerformerActivation.record!(organization: org, person: paige, month: this_month)
    PerformerActivation.record!(organization: org, person: paige, month: this_month)

    expect(described_class.new(org).active_count).to eq(1)
  end

  it "does not count an activation from another month" do
    paige = create(:person, name: "Paid Paige")
    PerformerActivation.record!(organization: org, person: paige, month: Date.current.beginning_of_month - 5)

    expect(described_class.new(org).active_count).to eq(0)
  end
end

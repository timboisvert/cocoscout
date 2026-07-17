# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffBillingService do
  let(:org) { create(:organization, :pro) }
  let(:this_month) { Date.current }

  def staff(name)
    person = create(:person, name: name)
    create(:organization_staff_member, organization: org, person: person)
    person
  end

  it "counts staff who were notified of a shift this month (via activations)" do
    worked = staff("Worked Wanda")
    staff("Idle Ike") # on staff but never notified

    StaffActivation.record!(organization: org, person: worked, month: this_month)

    svc = described_class.new(org)
    expect(svc.active_count).to eq(1)
    expect(svc.active_staff_cents).to eq(500)
  end

  it "bills only for active staff — paying people is included, no per-payment fee" do
    worked = staff("Worked Wanda")
    StaffActivation.record!(organization: org, person: worked, month: this_month)
    org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay")

    expect(described_class.new(org).monthly_estimate_cents).to eq(500) # $5 active only
  end

  it "does not count an activation from another month" do
    worked = staff("Worked Wanda")
    StaffActivation.record!(organization: org, person: worked, month: (Date.current.beginning_of_month - 5))

    expect(described_class.new(org).active_count).to eq(0)
  end

  it "stays billable even if the activation is the only trace (assignment removed)" do
    worked = staff("Worked Wanda")
    # Activation persists regardless of whether any assignment still exists.
    StaffActivation.record!(organization: org, person: worked, month: this_month)
    expect(described_class.new(org).active_count).to eq(1)
  end
end

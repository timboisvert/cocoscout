# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffBillingService do
  let(:org) { create(:organization, :pro) }
  let!(:house_role) { create(:house_role, organization: org) }
  let(:mid_month) { Date.current.beginning_of_month + 10 }

  def staff(name)
    person = create(:person, name: name)
    create(:organization_staff_member, organization: org, person: person)
    person
  end

  def schedule(person, on: mid_month)
    shift = create(:shift, organization: org, house_role: house_role,
                   starts_at: on.to_time.change(hour: 18), ends_at: on.to_time.change(hour: 22))
    create(:shift_assignment, shift: shift, person: person)
  end

  it "counts only staff scheduled at least one shift this month as active" do
    worked = staff("Worked Wanda")
    staff("Idle Ike") # on staff but not scheduled

    schedule(worked)

    svc = described_class.new(org)
    expect(svc.active_count).to eq(1)
    expect(svc.active_staff_cents).to eq(500)
  end

  it "adds this month's extra-payment fees to the estimate" do
    worked = staff("Worked Wanda")
    schedule(worked)
    org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay", extra_payment_fee_cents: 100)

    expect(described_class.new(org).monthly_estimate_cents).to eq(600) # $5 active + $1 fee
  end

  it "does not count a shift scheduled in another month" do
    worked = staff("Worked Wanda")
    schedule(worked, on: (Date.current.beginning_of_month - 5))

    expect(described_class.new(org).active_count).to eq(0)
  end

  it "no-ops usage reporting until a metered subscription item is configured" do
    expect(described_class.new(org).report_usage!).to eq(:not_configured)
  end
end

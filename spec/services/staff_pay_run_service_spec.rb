# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffPayRunService do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }

  def staff(name:, rate_cents:, bank: true)
    person = create(:person, name: name,
                    stripe_account_id: (bank ? "acct_#{name.parameterize}" : nil),
                    payouts_enabled: bank)
    create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: rate_cents)
  end

  describe ".payable_cents" do
    it "sums hours×rate plus bonus, reimbursement and tips" do
      expect(described_class.payable_cents(rate_cents: 2000, hours: 3.5, bonus_cents: 1000, reimbursement_cents: 250, tips_cents: 500)).to eq(8750)
    end
  end

  describe "tying pulled-in time entries" do
    it "marks the included entries paid and attached to the batch" do
      member = staff(name: "Tied Tom", rate_cents: 2000)
      e1 = create(:staff_time_entry, organization: org, person: member.person)
      e2 = create(:staff_time_entry, organization: org, person: member.person)
      other = create(:staff_time_entry, organization: org, person: member.person)

      result = described_class.build(
        organization: org, created_by: owner,
        lines: [ { staff_member: member, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0,
                   time_entry_ids: [ e1.id, e2.id ] } ]
      )

      expect(e1.reload.payout_batch).to eq(result.batch)
      expect(e1.reload).to be_paid
      expect(e2.reload).to be_paid
      expect(other.reload).not_to be_paid # not pulled in
    end
  end

  describe ".build" do
    it "creates a staff_pay batch with items + earnings for bankable staff, skipping the rest" do
      ready = staff(name: "Ready Rae", rate_cents: 2000)
      nobank = staff(name: "Nobank Nia", rate_cents: 2000, bank: false)

      result = nil
      expect {
        result = described_class.build(
          organization: org, created_by: owner,
          lines: [
            { staff_member: ready, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 },
            { staff_member: nobank, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 }
          ]
        )
      }.to change(PayoutBatch, :count).by(1)

      batch = result.batch
      expect(batch.kind).to eq("staff_pay")
      expect(batch.items.map(&:payee)).to eq([ ready.person ])
      expect(batch.total_cents).to eq(8000)
      # earning posted so the worker's balance reflects it before it's paid down
      expect(org.payout_balance_cents_for(ready.person)).to eq(8000)
      expect(result.skipped.map { |s| s[:member] }).to eq([ nobank ])
    end

    it "charges the $1 extra-payment fee after 2 paid runs in a month" do
      rae = staff(name: "Rae", rate_cents: 1000)
      # Two already-paid items this month.
      2.times do
        b = org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay")
        b.items.create!(payee: rae.person, amount_cents: 1000, status: "paid", paid_at: Time.current)
      end

      result = described_class.build(
        organization: org, created_by: owner,
        lines: [ { staff_member: rae, hours: 1, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 } ]
      )
      expect(result.batch.extra_payment_fee_cents).to eq(100)
    end
  end
end

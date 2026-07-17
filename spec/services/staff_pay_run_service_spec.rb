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

  # A 5-hour (18:00–23:00) time entry tied to a shift for the given house role.
  def role_entry(person, house_role)
    shift = create(:shift, house_role: house_role)
    assignment = create(:shift_assignment, shift: shift, person: person)
    create(:staff_time_entry, :from_shift, organization: org, person: person, shift_assignment: assignment)
  end

  describe ".payable_cents" do
    it "sums worked pay plus bonus, reimbursement and tips" do
      expect(described_class.payable_cents(worked_cents: 7000, bonus_cents: 1000, reimbursement_cents: 250, tips_cents: 500)).to eq(8750)
    end
  end

  describe ".worked_cents" do
    it "pays the member's default rate on manually entered hours" do
      member = staff(name: "Manual Mo", rate_cents: 2000)
      expect(described_class.worked_cents(organization: org, member: member, hours: 3.5)).to eq(7000)
    end

    it "pays each pulled entry at its own role's rate" do
      member = staff(name: "Roley Rae", rate_cents: 1300) # default $13/hr
      bartender = create(:house_role, organization: org, name: "Bartender")
      barback = create(:house_role, organization: org, name: "Barback")
      member.sync_role_qualifications!(role_ids: [ bartender.id, barback.id ],
                                       rates: { bartender.id => "15", barback.id => "18" })

      bar_entry = role_entry(member.person, bartender)     # 5h × $15 = 7500
      back_entry = role_entry(member.person, barback)      # 5h × $18 = 9000

      worked = described_class.worked_cents(organization: org, member: member,
                                            time_entry_ids: [ bar_entry.id, back_entry.id ])
      expect(worked).to eq(16_500)
    end
  end

  describe "tying pulled-in time entries" do
    it "marks the included entries paid and attached to the batch" do
      member = staff(name: "Tied Tom", rate_cents: 2000)
      e1 = create(:staff_time_entry, organization: org, person: member.person)
      e2 = create(:staff_time_entry, organization: org, person: member.person)
      other = create(:staff_time_entry, organization: org, person: member.person)

      result = described_class.add_lines!(
        organization: org, created_by: owner,
        lines: [ { staff_member: member, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0,
                   time_entry_ids: [ e1.id, e2.id ] } ]
      )

      expect(e1.reload.payout_batch).to eq(result.batch)
      expect(e1.reload).to be_paid
      expect(e1).to be_approved # paying implies approval
      expect(e2.reload).to be_paid
      expect(other.reload).not_to be_paid # not pulled in
    end
  end

  describe ".add_lines!" do
    it "adds every payee with a positive amount to the open staffing run, including those without a bank" do
      ready = staff(name: "Ready Rae", rate_cents: 2000)
      nobank = staff(name: "Nobank Nia", rate_cents: 2000, bank: false)

      result = nil
      expect {
        result = described_class.add_lines!(
          organization: org, created_by: owner,
          lines: [
            { staff_member: ready, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 },
            { staff_member: nobank, hours: 4, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 }
          ]
        )
      }.to change(PayoutBatch, :count).by(1)

      batch = result.batch
      expect(batch.kind).to eq("staff_pay")
      expect(batch.open?).to be(true)
      expect(batch.items.map(&:payee)).to match_array([ ready.person, nobank.person ])
      expect(batch.total_cents).to eq(16_000)
      expect(result.added).to eq(2)
      # earning posted so each worker's balance reflects it before it's paid down
      expect(org.payout_balance_cents_for(ready.person)).to eq(8000)
    end

    it "records a contribution per component (worked / bonus / reimbursement / tips)" do
      member = staff(name: "Detail Dee", rate_cents: 2000)
      result = described_class.add_lines!(
        organization: org, created_by: owner,
        lines: [ { staff_member: member, hours: 2, bonus_cents: 500, reimbursement_cents: 250, tips_cents: 1000 } ]
      )

      item = result.batch.items.find_by(payee: member.person)
      labels = item.payout_contributions.pluck(:label)
      expect(labels).to include("Worked hours (2h)", "Bonus", "Reimbursement", "Tips")
      # 2h × $20 + $5 + $2.50 + $10 = $57.50
      expect(item.amount_cents).to eq(5750)
      expect(item.payout_contributions.sum(:amount_cents)).to eq(item.amount_cents)
    end

    it "accumulates a second add into the same open run and the same payee's item" do
      member = staff(name: "Again Amy", rate_cents: 2000)
      first = described_class.add_lines!(
        organization: org, created_by: owner,
        lines: [ { staff_member: member, hours: 1, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 } ]
      )
      second = nil
      expect {
        second = described_class.add_lines!(
          organization: org, created_by: owner,
          lines: [ { staff_member: member, hours: 2, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0 } ]
        )
      }.not_to change(PayoutBatch, :count)

      expect(second.batch).to eq(first.batch)
      item = second.batch.items.find_by(payee: member.person)
      expect(item.payout_contributions.count).to eq(2)
      expect(item.amount_cents).to eq(6000) # (1h + 2h) × $20
    end
  end
end

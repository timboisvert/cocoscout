# frozen_string_literal: true

require "rails_helper"

# Deducted service charges belong inside the settlement that nets them out,
# not beside it as six things to chase.
RSpec.describe "Contract#payment_schedule_groups", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, organization: org, production: production) }

  def settlement(due)
    contract.contract_payments.create!(description: "Ticket revenue less $750.00 fee — week of #{due.strftime('%b %-d')}",
                                       amount: 0, amount_tbd: true, direction: "outgoing", due_date: due)
  end

  def booth_tech(due)
    contract.contract_payments.create!(description: "Booth Tech — #{due.strftime('%b %-d, %Y')}", amount: 50,
                                       direction: "incoming", due_date: due, settlement_method: "payout_deduction")
  end

  it "folds each week's charges into that week's settlement" do
    week1 = settlement(Date.new(2026, 11, 7))
    week2 = settlement(Date.new(2026, 11, 14))
    [ 5, 6, 7 ].each { |d| booth_tech(Date.new(2026, 11, d)) }
    [ 12, 13, 14 ].each { |d| booth_tech(Date.new(2026, 11, d)) }

    groups = contract.payment_schedule_groups

    expect(groups.size).to eq(2)
    first = groups.find { |g| g[:payment] == week1 }
    expect(first[:deductions].size).to eq(3)
    expect(first[:deduction_total]).to eq(150.0)
    second = groups.find { |g| g[:payment] == week2 }
    expect(second[:deductions].size).to eq(3)
  end

  it "leaves a directly-collected charge as its own row" do
    settlement(Date.new(2026, 11, 7))
    direct = contract.contract_payments.create!(description: "Cleaning deposit", amount: 200,
                                                direction: "incoming", due_date: Date.new(2026, 11, 5))

    rows = contract.payment_schedule_groups.map { |g| g[:payment] }
    expect(rows).to include(direct)
  end

  it "leaves a deducted charge standing alone when there's no settlement to fold into" do
    charge = booth_tech(Date.new(2026, 11, 5))

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).to eq([ charge ])
    expect(groups.first[:deductions]).to be_empty
  end

  it "keeps a charge that was actually paid (cash/check) visible instead of hiding it in a settlement" do
    settlement(Date.new(2026, 11, 7))
    paid = contract.contract_payments.create!(description: "Booth Tech — Nov 5, 2026", amount: 50,
                                              direction: "incoming", due_date: Date.new(2026, 11, 5),
                                              settlement_method: "payout_deduction",
                                              status: "paid", paid_date: Date.new(2026, 11, 5),
                                              payment_method: "check")

    expect(contract.payment_schedule_groups.map { |g| g[:payment] }).to include(paid)
  end

  it "keeps a deduction-settled charge folded into its settlement — no money moved, so no Paid row" do
    host = settlement(Date.new(2026, 11, 7))
    fee = contract.contract_payments.create!(description: "Booth Tech — Nov 7, 2026", amount: 50,
                                             direction: "incoming", due_date: Date.new(2026, 11, 7),
                                             settlement_method: "payout_deduction",
                                             status: "paid", paid_date: Date.new(2026, 11, 7),
                                             payment_method: "payout_deduction")

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).not_to include(fee)
    host_group = groups.find { |g| g[:payment] == host }
    expect(host_group[:deductions]).to include(fee)
  end

  it "folds a deducted fee into its own settlement even once that settlement is paid" do
    earlier = contract.contract_payments.create!(description: "Revenue Share - Event 1", amount: 320,
                                                 direction: "outgoing", due_date: Date.new(2026, 10, 3),
                                                 status: "paid", paid_date: Date.new(2026, 10, 5))
    host = contract.contract_payments.create!(description: "Nov 7 — 50% to them", amount: 257.50,
                                              direction: "outgoing", due_date: Date.new(2026, 11, 7),
                                              status: "paid", paid_date: Date.new(2026, 11, 9))
    fee = contract.contract_payments.create!(description: "Booth Tech — Nov 7, 2026", amount: 50,
                                             direction: "incoming", due_date: Date.new(2026, 11, 7),
                                             settlement_method: "payout_deduction",
                                             status: "paid", paid_date: Date.new(2026, 11, 7),
                                             payment_method: "payout_deduction")

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).not_to include(fee)
    expect(groups.find { |g| g[:payment] == earlier }[:deductions]).to be_empty
    expect(groups.find { |g| g[:payment] == host }[:deductions]).to eq([ fee ])
  end

  # Contract 111, 2026-10-20: the Oct 16 share was in a funded run ($342.50 less
  # two $50 booth techs = $242.50) when an amendment added an Oct 20 rehearsal.
  # The page showed it netted from the in-flight share ($192.50) — it can't be.
  context "when the settlement is already in a payout run" do
    let(:batch) { org.payout_batches.create!(kind: "payout", status: "funding", trigger: "manual", funding_status: "processing", total_cents: 24_250) }
    let(:payee) { create(:person) }
    let!(:share) do
      contract.contract_payments.create!(description: "Oct 16 — 50% to them", amount: 342.50,
                                         direction: "outgoing", due_date: Date.new(2026, 10, 16))
    end

    before do
      item = batch.items.create!(payee: payee, amount_cents: 24_250, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee, source: share,
                                 amount_cents: 34_250, label: "Share")
    end

    def deducted(due)
      contract.contract_payments.create!(description: "Booth Tech — #{due.strftime('%b %-d, %Y')}", amount: 50,
                                         direction: "incoming", due_date: due, settlement_method: "payout_deduction",
                                         status: "paid", paid_date: Date.new(2026, 10, 17),
                                         payment_method: "payout_deduction", reference_number: "payout_run_#{batch.id}")
    end

    it "keeps a charge added afterwards off the in-flight share, as a payable row of its own" do
      deducted(Date.new(2026, 8, 26))
      deducted(Date.new(2026, 10, 16))
      rehearsal = contract.contract_payments.create!(description: "Rehearsal — Oct 20, 2026", amount: 50,
                                                     direction: "incoming", due_date: Date.new(2026, 10, 20),
                                                     settlement_method: "payout_deduction")

      groups = contract.reload.payment_schedule_groups
      host = groups.find { |g| g[:payment] == share }
      expect(host[:deduction_total]).to eq(100.0)
      expect(groups.map { |g| g[:payment] }).to include(rehearsal)
      expect(rehearsal.reload.deduct_from_payout?).to be(false)
      expect(rehearsal.collectable_online?).to be(true)
    end

    it "folds a deducted charge into the run it rode out on, not the next settlement by date" do
      earlier = contract.contract_payments.create!(description: "Sep 5 — 50% to them", amount: 300,
                                                   direction: "outgoing", due_date: Date.new(2026, 9, 5),
                                                   status: "paid", paid_date: Date.new(2026, 9, 7))
      aug = deducted(Date.new(2026, 8, 26))

      groups = contract.reload.payment_schedule_groups
      expect(groups.find { |g| g[:payment] == earlier }[:deductions]).to be_empty
      expect(groups.find { |g| g[:payment] == share }[:deductions]).to eq([ aug ])
    end
  end

  # Contract 92 (Tim, 2026-11-22): every charge a run settled piled onto the
  # first share after it, so a $14.00 share read "We paid them −$202.00".
  # Each charge belongs to the settlement whose run took it.
  describe "charges settled by offset" do
    def share(due, amount, reference)
      contract.contract_payments.create!(description: "#{due.strftime('%b %-d')} — 40% to them", amount: amount, direction: "outgoing",
                                         due_date: due, status: "paid", paid_date: due + 2, payment_method: "offset",
                                         reference_number: reference)
    end

    def charge(due, amount, reference, description: "Rehearsal — #{due.strftime('%b %-d, %Y')}")
      contract.contract_payments.create!(description: description, amount: amount, direction: "incoming", due_date: due,
                                         settlement_method: "payout_deduction", status: "paid", paid_date: due,
                                         payment_method: "payout_deduction", reference_number: reference)
    end

    it "puts each charge under the share whose run took it, not the first share after it" do
      first = share(Date.new(2026, 9, 17), 14, "offset against rehearsal fees")
      oct8 = share(Date.new(2026, 10, 8), 18, "offset against services (run #29)")
      oct22 = share(Date.new(2026, 10, 22), 60, "offset against services (run #32)")
      aug26 = charge(Date.new(2026, 8, 26), 6, "offset_run_29", description: "Rehearsal balance — Aug 26, 2026")
      sep6 = charge(Date.new(2026, 9, 6), 12, "offset_run_29")
      sep6_rest = charge(Date.new(2026, 9, 6), 48, "offset_run_32", description: "Rehearsal balance — Sep 6, 2026")

      groups = contract.payment_schedule_groups.index_by { |g| g[:payment] }
      expect(groups[first][:deductions]).to be_empty
      expect(groups[oct8][:deductions]).to contain_exactly(aug26, sep6)
      expect(groups[oct22][:deductions]).to contain_exactly(sep6_rest)
    end

    it "carries shares one offset settled together with the last of them" do
      s1 = share(Date.new(2026, 9, 17), 14, "offset against rehearsal fees")
      s2 = share(Date.new(2026, 9, 24), 20, "offset against rehearsal fees")
      s3 = share(Date.new(2026, 10, 1), 80, "offset against rehearsal fees")
      named = "offset against shares ##{s1.id}, ##{s2.id}, ##{s3.id}"
      aug23 = charge(Date.new(2026, 8, 23), 60, named)
      aug26 = charge(Date.new(2026, 8, 26), 54, named)

      groups = contract.payment_schedule_groups.index_by { |g| g[:payment] }
      expect(groups[s3][:deductions]).to contain_exactly(aug23, aug26)
      expect(groups[s3][:co_shares]).to eq([ s1, s2 ])
      expect(groups[s1][:deductions]).to be_empty
    end
  end
end

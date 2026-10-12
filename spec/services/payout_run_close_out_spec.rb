# frozen_string_literal: true

require "rails_helper"

# Closing out a funded run that's paid except for people with no bank: they
# move to the standing "Waiting on bank info" run, the old run closes as paid,
# their money stays set aside, and the waiting run pays each of them once
# they connect (Tim, 2026-10-12).
RSpec.describe PayoutRunCloseOut do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org) }
  let(:banked) { create(:person, name: "Banked Bea", stripe_account_id: "acct_bea", payouts_enabled: true) }
  let(:unbanked) { create(:person, name: "Pat Performer") }

  before { allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_pat")) }

  # A funded run: Bea paid, Pat waiting on a bank.
  def funded_run(waiting: unbanked, waiting_amount: 40)
    show = create(:show, production: production, event_type: :show, date_and_time: 3.days.ago)
    payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 60 + waiting_amount)
    ShowPayoutLineItem.create!(show_payout: payout, payee: banked, amount: 60)
    ShowPayoutLineItem.create!(show_payout: payout, payee: waiting, amount: waiting_amount)
    PerformerPayoutRunService.add_show_payout!(payout)
    batch = PayoutBatch.current_open_draft(org)
    batch.update!(status: "partially_paid", funding_status: "succeeded")
    batch.items.find_by(payee: banked).mark_paid!(transfer_id: "tr_bea")
    batch.reload
  end

  it "moves the people waiting on a bank to the waiting run and closes the old run as paid, money still set aside" do
    run = funded_run
    expect(described_class.closable?(run)).to be(true)
    set_aside = OrgCashEntry.committed_cents(org)

    result = described_class.close!(run, by: owner)

    expect(run.reload).to have_attributes(status: "completed", total_cents: 6_000, closed_out_by_id: owner.id)
    expect(run.closed_out_at).to be_present
    waiting = result.waiting_run
    expect(waiting).to have_attributes(waiting_on_banks: true, status: "partially_paid", funding_status: "succeeded", total_cents: 4_000)
    expect(waiting.items.sole).to have_attributes(payee_id: unbanked.id, amount_cents: 4_000, status: "pending")
    expect(waiting.payout_contributions.pluck(:moved_from_batch_id)).to eq([ run.id ])
    expect(run.moved_out_contributions.map(&:payee)).to eq([ unbanked ])
    expect(OrgCashEntry.committed_cents(org)).to eq(set_aside)
    expect(waiting.kind_label).to eq("Waiting on bank info")
  end

  it "keeps one line for someone waiting from two runs" do
    first = funded_run
    described_class.close!(first, by: owner)
    second = funded_run(waiting_amount: 25)
    result = described_class.close!(second, by: owner)

    item = result.waiting_run.items.sole
    expect(item.amount_cents).to eq(6_500)
    expect(item.payout_contributions.pluck(:moved_from_batch_id)).to contain_exactly(first.id, second.id)
    expect(result.waiting_run.total_cents).to eq(6_500)
  end

  it "waits while anyone unpaid could be paid now" do
    run = funded_run
    unbanked.update!(stripe_account_id: "acct_pat", payouts_enabled: true)

    expect(described_class.closable?(run.reload)).to be(false)
    expect { described_class.close!(run, by: owner) }.to raise_error(described_class::Error)
  end

  it "pays them from the waiting run once they connect a bank, then the waiting run is done" do
    run = funded_run
    waiting = described_class.close!(run, by: owner).waiting_run
    unbanked.update!(stripe_account_id: "acct_pat", payouts_enabled: true)

    PayoutBatchService.pay_remaining!(waiting.reload)

    expect(waiting.items.sole.reload.status).to eq("paid")
    expect(waiting.reload.status).to eq("completed")
    expect(Stripe::Transfer).to have_received(:create).with(hash_including(amount: 4_000, destination: "acct_pat"), anything)
  end

  it "never closes out the waiting run itself" do
    run = funded_run
    waiting = described_class.close!(run, by: owner).waiting_run
    expect(described_class.closable?(waiting)).to be(false)
  end
end

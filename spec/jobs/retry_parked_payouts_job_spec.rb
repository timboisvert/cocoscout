# frozen_string_literal: true

require "rails_helper"

# Money debited from the org and parked on a funded run used to move only when
# a manager noticed the "Pay remaining" button had lit up. Now it moves itself.
RSpec.describe RetryParkedPayoutsJob, type: :job do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let(:parked) { create(:person, name: "Sam Staffer") }

  # Funded, one person paid, one still parked with no bank.
  def parked_run!(payee: parked, bank: false)
    batch = org.payout_batches.create!(kind: "staff_pay", status: "partially_paid",
                                       trigger: "manual", funding_status: "succeeded",
                                       total_cents: 5_000)
    allow_any_instance_of(Person).to receive(:can_receive_payouts?).and_return(bank)
    batch.items.create!(payee: payee, amount_cents: 5_000, status: "pending")
    batch
  end

  it "pays a parked person once they can receive payouts" do
    batch = parked_run!(bank: true)
    allow(PayoutBatchService).to receive(:pay_remaining!)

    described_class.perform_now

    expect(PayoutBatchService).to have_received(:pay_remaining!).with(batch)
  end

  it "leaves a run alone while the person still has no bank" do
    parked_run!(bank: false)
    allow(PayoutBatchService).to receive(:pay_remaining!)

    described_class.perform_now

    expect(PayoutBatchService).not_to have_received(:pay_remaining!)
  end

  it "ignores runs that haven't funded — nothing has been promised yet" do
    batch = org.payout_batches.create!(kind: "staff_pay", status: "partially_paid",
                                       trigger: "manual", funding_status: "processing", total_cents: 5_000)
    allow_any_instance_of(Person).to receive(:can_receive_payouts?).and_return(true)
    batch.items.create!(payee: parked, amount_cents: 5_000, status: "pending")
    allow(PayoutBatchService).to receive(:pay_remaining!)

    described_class.perform_now

    expect(PayoutBatchService).not_to have_received(:pay_remaining!)
  end

  it "scoped to one payee, skips runs waiting on somebody else" do
    other = create(:person)
    parked_run!(payee: other, bank: true)
    allow(PayoutBatchService).to receive(:pay_remaining!)

    described_class.perform_now(payee: parked)

    expect(PayoutBatchService).not_to have_received(:pay_remaining!)
  end

  it "one failing run doesn't stop the sweep" do
    parked_run!(bank: true)
    parked_run!(bank: true)
    call = 0
    allow(PayoutBatchService).to receive(:pay_remaining!) { call += 1; raise "boom" if call == 1 }

    expect { described_class.perform_now }.not_to raise_error
    expect(call).to eq(2)
  end
end

RSpec.describe "PayoutBatch retry timing", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }

  it "names the next sweep only while somebody is actually waiting" do
    waiting = org.payout_batches.create!(kind: "staff_pay", status: "partially_paid", trigger: "manual",
                                         funding_status: "succeeded", total_cents: 100)
    waiting.items.create!(payee: create(:person), amount_cents: 100, status: "pending")
    done = org.payout_batches.create!(kind: "staff_pay", status: "completed", trigger: "manual",
                                      funding_status: "succeeded", total_cents: 100)

    expect(waiting.next_auto_retry_at).to be_present
    expect(waiting.next_auto_retry_at.hour).to eq(PayoutBatch::AUTO_RETRY_HOUR)
    expect(waiting.next_auto_retry_at).to be > Time.zone.now
    expect(done.next_auto_retry_at).to be_nil
  end
end

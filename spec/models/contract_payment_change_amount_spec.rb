# frozen_string_literal: true

require "rails_helper"

# Changing what they owe, with a note (Tim, 2026-11-22): less, or $0 when the
# organization won't collect the last bit of a rehearsal no share was left to
# cover. At $0 nothing is owed, it isn't overdue, the pay link stops, and the
# books withdraw what it would have earned.
RSpec.describe "ContractPayment#change_amount!", type: :model do
  let(:manager) { create(:user) }
  let(:org) { create(:organization, owner: manager) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, organization: org, production: production) }
  let!(:balance) do
    contract.contract_payments.create!(description: "Rehearsal balance — Sep 13, 2026", amount: 24, direction: "incoming",
                                       due_date: 2.months.ago.to_date)
  end

  it "sets it to $0 with a note: settled, not overdue, nothing to collect, and off the books" do
    expect(balance).to be_overdue
    expect(balance).to be_collectable_online
    BooksOutsidePoster.post_contract_payment!(balance)
    expect(JournalEntry.live.where(source_type: "ContractPayment", source_id: balance.id)).to exist

    expect(balance.change_amount!(amount: "0", note: "Not charging them for the last bit.", by: manager)).to be(true)

    balance.reload
    expect(balance).to have_attributes(amount: 0, status: "paid", payment_method: "set_to_zero", paid_date: Date.current,
                                       amount_before_change: 24, amount_change_note: "Not charging them for the last bit.",
                                       amount_changed_by: manager)
    expect(balance).to be_set_to_zero
    expect(balance).not_to be_overdue
    expect(balance).not_to be_collectable_online
    expect(balance.received_via_label).to eq("Set to $0")
    expect(JournalEntry.live.where(source_type: "ContractPayment", source_id: balance.id)).not_to exist
  end

  it "sends no receipt for $0" do
    expect { balance.change_amount!(amount: 0, note: nil, by: manager) }.not_to have_enqueued_job(ContractPaymentReceiptJob)
  end

  it "voids an invoice someone opened" do
    invoice = Invoice.for!(balance)
    balance.change_amount!(amount: 0, note: nil, by: manager)
    expect(invoice.reload).to be_void
  end

  it "changes it to a smaller amount that's still owed" do
    balance.change_amount!(amount: "$10.50", note: "Split the difference.", by: manager)
    expect(balance.reload).to have_attributes(amount: 10.5, status: "pending", amount_before_change: 24)
    expect(balance).to be_collectable_online
  end

  it "puts it back from $0, owed again, keeping the amount it first was" do
    balance.change_amount!(amount: 0, note: "Never mind it.", by: manager)
    balance.change_amount!(amount: 24, note: "We are charging it after all.", by: manager)

    expect(balance.reload).to have_attributes(amount: 24, status: "pending", payment_method: nil, paid_date: nil, amount_before_change: 24)
    expect(balance).to be_overdue
  end

  it "refuses a negative amount or one that isn't a number" do
    expect(balance.change_amount!(amount: "-5", note: nil, by: manager)).to be(false)
    expect(balance.change_amount!(amount: "lots", note: nil, by: manager)).to be(false)
    expect(balance.reload.amount).to eq(24)
  end

  it "is offered for money they owe directly, not for money we owe or an amount not known yet" do
    expect(balance).to be_amount_changeable
    ours = contract.contract_payments.create!(description: "Their share", amount: 30, direction: "outgoing", due_date: Date.current)
    unknown = contract.contract_payments.create!(description: "Settlement", amount: 0, amount_tbd: true, direction: "incoming",
                                                 due_date: Date.current)

    expect(ours).not_to be_amount_changeable
    expect(unknown).not_to be_amount_changeable
  end
end

# frozen_string_literal: true

require "rails_helper"

# The week Settle up started, the payout run already in flight carried that
# week's tips, typed by hand with their dates. A day's register then splits
# the same tips again: what was typed counts as paid, so nobody gets a
# day's tips twice (Tim, 2026-11-11).
RSpec.describe TipShare do
  let(:org) { create(:organization, :pro) }
  let(:bartender) { create(:person) }
  let(:date) { Date.new(2026, 11, 6) }
  let(:day) { SettlementDay.create!(organization: org, date: date, status: "settled", settled_at: Time.current) }

  def typed_tips!(person, entries, status: "funding", label: "Tips")
    batch = create(:payout_batch, organization: org, status: status)
    cents = entries.sum { |_, amount| amount }
    item = PayoutBatchItem.create!(payout_batch: batch, payee: person, amount_cents: cents, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, amount_cents: cents, label: label, category: "staffing",
                               worksheet: entries.map { |on, amount| { "date" => on, "amount_cents" => amount } })
  end

  it "counts tips typed onto a run for the day as paid, so the share doesn't wait to be paid again" do
    typed_tips!(bartender, [ [ "2026-11-04", 3_832 ], [ "2026-11-06", 6_329 ] ])

    share = day.tip_shares.create!(person: bartender, amount_cents: 6_329)

    expect(share.paid_cents).to eq(6_329)
    expect(share.owed_cents).to eq(0)
    expect(described_class.waiting_for(org)).to be_empty
    expect(described_class.overpaid_for(org)).to be_empty
  end

  it "leaves only the difference waiting, or coming back, when the amounts differ" do
    typed_tips!(bartender, [ [ "2026-11-06", 5_000 ] ])
    more = day.tip_shares.create!(person: bartender, amount_cents: 6_329)
    expect(more.owed_cents).to eq(1_329)
    expect(described_class.waiting_for(org)).to eq([ more ])

    more.update!(amount_cents: 4_000)
    expect(more.owed_cents).to eq(-1_000)
    expect(described_class.overpaid_for(org)).to eq([ more ])
  end

  it "counts nothing typed for another day, another person, a canceled run, or cash tips" do
    typed_tips!(bartender, [ [ "2026-11-05", 6_329 ] ])
    typed_tips!(create(:person), [ [ "2026-11-06", 6_329 ] ])
    typed_tips!(bartender, [ [ "2026-11-06", 6_329 ] ], status: "canceled")
    typed_tips!(bartender, [ [ "2026-11-06", 6_329 ] ], label: "Cash tips (recorded)")

    share = day.tip_shares.create!(person: bartender, amount_cents: 6_329)

    expect(share.paid_cents).to be_nil
    expect(described_class.waiting_for(org)).to eq([ share ])
  end

  it "doesn't count a run line that a share itself put there" do
    share = day.tip_shares.create!(person: bartender, amount_cents: 6_329)
    line = typed_tips!(bartender, [ [ "2026-11-06", 6_329 ] ])
    share.update!(payout_contribution: line)

    expect(described_class.typed_on_runs(org, date)).to be_empty
  end
end

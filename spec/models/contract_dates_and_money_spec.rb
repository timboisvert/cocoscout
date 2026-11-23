# frozen_string_literal: true

require "rails_helper"

# The contract page's Dates and money (Tim, 2026-11-22, design B): a row per
# booked date with its money, money on unbooked days as rows of their own, and
# what's left owed once no share can cover it in a box under the list, never
# on the first date it came from.
RSpec.describe ContractDatesAndMoney, type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, :revenue_share_per_event, organization: org, production: production, contractor_name: "Improvised Animorphs") }
  let(:now) { Time.zone.local(2026, 11, 22, 12) }

  around { |example| travel_to(now) { example.run } }

  def booked(day, event_type)
    rental = create(:space_rental, contract: contract, starts_at: day.in_time_zone.change(hour: 12), ends_at: day.in_time_zone.change(hour: 14), confirmed: true)
    create(:show, production: production, space_rental: rental, event_type: event_type, date_and_time: day.in_time_zone.change(hour: 12))
  end

  let!(:rehearsal) { booked(Date.new(2026, 9, 13), "rehearsal") }
  let!(:night) { booked(Date.new(2026, 11, 19), "show") }
  let!(:share) do
    contract.contract_payments.create!(description: "Nov 19 — 40% to them", amount: 24, direction: "outgoing", show: night,
                                       due_date: Date.new(2026, 11, 19), status: "paid", paid_date: Date.new(2026, 11, 20),
                                       payment_method: "offset", reference_number: "offset against services (run #36)")
  end
  let!(:covered) do
    contract.contract_payments.create!(description: "Rehearsal — Sep 13, 2026", amount: 36, direction: "incoming", show: rehearsal,
                                       due_date: Date.new(2026, 9, 13), settlement_method: "payout_deduction", status: "paid",
                                       paid_date: Date.new(2026, 11, 20), payment_method: "payout_deduction", reference_number: "offset_run_36")
  end
  let!(:left) do
    contract.contract_payments.create!(description: "Rehearsal balance — Sep 13, 2026", amount: 24, direction: "incoming", show: rehearsal,
                                       due_date: Date.new(2026, 9, 13), settlement_method: "payout_deduction")
  end

  subject(:money) { described_class.new(contract.reload) }

  it "gives each booked date one row, its charge pieces read as one charge" do
    rows = money.rows
    expect(rows.map(&:date)).to eq([ Date.new(2026, 9, 13), Date.new(2026, 11, 19) ])

    sep13 = rows.first
    expect(sep13.lines.size).to eq(1)
    expect(sep13.lines.first).to have_attributes(text: "$36.00 paid from the shares on Nov 20. $24.00 is still owed.",
                                                 amount: "$60.00", note: "$24.00 owed", tone: :owed)
    expect(sep13.charges.map(&:total)).to eq([ 60.0 ])
  end

  it "says where a share went, without a negative payment anywhere" do
    nov19 = money.rows.last
    expect(nov19.lines.first.text).to eq("The $24.00 share went toward what Improvised Animorphs owed. Settled Nov 20.")
    expect(nov19.expanded).to eq([ share ])
    expect(money.host_for(covered)).to eq(share)
  end

  it "keeps what no share is left to cover in the box under the list, not on its date's opened row" do
    expect(left.reload.deduct_from_payout?).to be(false)
    expect(money.owed).to eq([ left ])
    expect(money.owed_total).to eq(24.0)
    expect(money.rows.flat_map(&:expanded)).not_to include(left)
    expect(described_class.owed_label(left)).to eq("the rest of the rehearsal on Sep 13")
  end

  it "keeps one set to $0 in the box, settled, with nothing owed" do
    left.change_amount!(amount: 0, note: "Not charging for it.", by: nil)
    money = described_class.new(contract.reload)

    expect(money.owed).to eq([ left ])
    expect(money.owed_pending).to be_empty
    expect(money.rows.first.lines.first).to have_attributes(text: "$36.00 paid from the shares on Nov 20. $24.00 set to $0 on Nov 22.",
                                                            amount: "$60.00", note: "Paid", tone: :neutral)
  end

  it "gives money due on a day with nothing booked a row of its own" do
    deposit = contract.contract_payments.create!(description: "Deposit", amount: 200, direction: "incoming", due_date: Date.new(2026, 9, 1))

    row = described_class.new(contract.reload).rows.first
    expect(row).to have_attributes(kind: :payment, date: Date.new(2026, 9, 1), payment: deposit, title: "Deposit",
                                   subtitle: "Nothing is booked this day", open: true)
    expect(row.lines.first).to have_attributes(text: "Due Sep 1, and overdue.", amount: "$200.00", tone: :owed)
  end
end

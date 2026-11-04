# frozen_string_literal: true

require "rails_helper"

# Tips go to whoever was working (plan §9.14): a two-bartender night, a bar
# back's cut off the top, and a span with nobody on.
RSpec.describe TipSplit do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "calendar") }
  let(:bartender) { org.house_roles.create!(name: "Bartender") }
  let(:bar_back) { org.house_roles.create!(name: "Bar back") }
  let(:door) { org.house_roles.create!(name: "Door") }
  let(:rule) { org.create_tip_rule!(enabled: true, role_shares: { bartender.id.to_s => { "kind" => "equal" }, bar_back.id.to_s => { "kind" => "percent", "percent" => 15 } }) }
  let(:miles) { create(:person, name: "Miles") }
  let(:camille) { create(:person, name: "Camille") }
  let(:jo) { create(:person, name: "Jo Back") }
  let(:pat) { create(:person, name: "Pat Door") }
  let(:night) { Time.zone.local(2026, 10, 30) }

  def span(person, from, to, role)
    SettleUp::Worker.new(person: person, staff_member: nil, spans: [ TipSplit::Span.new(from: night + from.hours, to: night + to.hours, house_role_id: role.id) ])
  end

  # $10 of tips in every quarter hour from `from` to `to`.
  def tips(from, to, cents: 1_000, orders: 2)
    (from * 4...to * 4).to_h { |q| [ SquareSync.quarter_key(night + (q * 15).minutes), { "cents" => cents, "orders" => orders } ] }
  end

  it "gives each bartender what rang up while they were on, and splits the hours they shared" do
    # Miles 6 to 10, Camille 8 to midnight: 6–8 is Miles's ($80), 8–10 is shared ($40 each), 10–12 is Camille's ($80).
    split = described_class.new(rule: rule, tips_cents: 24_000, tips_by_time: tips(18, 24), workers: [ span(miles, 18, 22, bartender), span(camille, 20, 24, bartender), span(pat, 18, 24, door) ], shares: [])
    expect(split).to be_applies
    rows = split.rows.index_by { |r| r.person.name }
    expect(rows.keys).to contain_exactly("Miles", "Camille")
    expect(rows["Miles"].cents).to eq(12_000)
    expect(rows["Camille"].cents).to eq(12_000)
    expect(rows["Miles"].on_orders).to eq(32)
    expect(rows["Miles"].span_words).to eq("6 pm to 10 pm")
    expect(rows["Miles"].how).to eq("From 32 orders while on.")
    expect(split.pool.cents).to eq(0)
    expect(split.rows.sum(&:cents)).to eq(24_000)
  end

  it "takes the bar back's cut off the top while they are on, and only then" do
    # Jo on 8 to 10 takes 15% of those two hours ($80 → $12); Miles keeps the rest of the night.
    split = described_class.new(rule: rule, tips_cents: 24_000, tips_by_time: tips(18, 24), workers: [ span(miles, 18, 24, bartender), span(jo, 20, 22, bar_back) ], shares: [])
    rows = split.rows.index_by { |r| r.person.name }
    expect(rows["Jo Back"].cents).to eq(1_200)
    expect(rows["Jo Back"].how).to eq("15% off the top while on.")
    expect(rows["Miles"].cents).to eq(22_800)
    expect(rows["Miles"].house_role).to eq(bartender)
  end

  it "pools what rang up with nobody on, splits it evenly, and says so" do
    # Nobody on 6 to 7 ($40 from 8 orders); Miles and Camille both on the rest.
    split = described_class.new(rule: rule, tips_cents: 24_000, tips_by_time: tips(18, 24), workers: [ span(miles, 19, 24, bartender), span(camille, 19, 24, bartender) ], shares: [])
    expect(split.pool).to eq(TipSplit::Pool.new(cents: 4_000, orders: 8))
    rows = split.rows.index_by { |r| r.person.name }
    expect(rows["Miles"].cents).to eq(12_000)
    expect(rows["Miles"].pool_cents).to eq(2_000)
    expect(rows["Miles"].how).to eq("From 40 orders while on, plus $20.00 from the pool.")
  end

  it "keeps a typed share as typed and works the rest out around it" do
    record = SettlementDay.create!(organization: org, date: night.to_date)
    typed = record.tip_shares.create!(person: camille, amount_cents: 5_000, source: "typed", method: "payout")
    split = described_class.new(rule: rule, tips_cents: 24_000, tips_by_time: tips(18, 24), workers: [ span(miles, 18, 24, bartender), span(camille, 18, 24, bartender) ], shares: [ typed ])
    rows = split.rows.index_by { |r| r.person.name }
    expect(rows["Camille"].cents).to eq(5_000)
    expect(rows["Camille"]).to be_typed
    expect(rows["Miles"].cents).to eq(19_000)
    expect(rows["Miles"].how).to eq("From 48 orders while on.")
  end

  it "does not apply when the rule is off, when the register has no times, or when nobody who shares was on" do
    expect(described_class.new(rule: nil, tips_cents: 1_000, tips_by_time: tips(18, 19), workers: [ span(miles, 18, 24, bartender) ], shares: [])).not_to be_applies
    expect(described_class.new(rule: rule, tips_cents: 1_000, tips_by_time: {}, workers: [ span(miles, 18, 24, bartender) ], shares: [])).not_to be_applies
    expect(described_class.new(rule: rule, tips_cents: 1_000, tips_by_time: tips(18, 19), workers: [ span(pat, 18, 24, door) ], shares: [])).not_to be_applies
  end
end

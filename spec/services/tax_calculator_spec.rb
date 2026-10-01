# frozen_string_literal: true

require "rails_helper"

# Tax the theater sets, worked out per ticket: added on top or included in the
# price, rates that stack, exemptions with a reason, and the most specific
# rule winning.
RSpec.describe TaxCalculator do
  let(:org) { create(:organization) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let(:tier) { create(:ticket_tier, ticket_listing: listing, price_cents: 2_000) }

  def rate(percent, name: "Sales tax")
    org.tax_rates.create!(name: name, rate_bps: (percent * 100).round)
  end

  def default_rule(rates, mode: "added")
    org.tax_rules.create!(money_kind: "tickets", mode: mode, tax_rate_ids: Array(rates).map(&:id))
  end

  it "charges nothing when the theater hasn't set any tax" do
    expect(described_class.for_ticket(listing, tier, 2_000)).to eq(TaxCalculator::NONE)
  end

  it "adds 10.25% on top of a $20 ticket" do
    default_rule(rate(10.25))
    result = described_class.for_ticket(listing, tier, 2_000)
    expect([ result.mode, result.tax_cents, result.added_cents ]).to eq([ "added", 205, 205 ])
    expect(result.lines.first.to_h.slice(:name, :rate_bps, :base_cents)).to eq(name: "Sales tax", rate_bps: 1_025, base_cents: 2_000)
  end

  it "finds the tax inside a price when it's included" do
    default_rule(rate(10.25), mode: "included")
    result = described_class.for_ticket(listing, tier, 2_000)
    expect([ result.tax_cents, result.added_cents ]).to eq([ 186, 0 ])
    expect(result.lines.first.base_cents + result.tax_cents).to eq(2_000)
  end

  it "stacks rates, and splits included tax between them without losing a cent" do
    city = rate(9, name: "City amusement tax")
    county = rate(3, name: "County amusement tax")
    default_rule([ city, county ])
    added = described_class.for_ticket(listing, tier, 2_000)
    expect(added.lines.map(&:tax_cents)).to eq([ 180, 60 ])

    org.tax_rules.first.update!(mode: "included")
    included = described_class.for_ticket(listing, tier, 2_001)
    expect(included.lines.sum(&:tax_cents) + included.lines.first.base_cents).to eq(2_001)
  end

  it "records an exempt sale with its reason and no tax" do
    org.tax_rules.create!(money_kind: "tickets", exempt: true, exemption_reason: "Live performance, venue under 1,500 seats")
    result = described_class.for_ticket(listing, tier, 2_000)
    expect(result.tax_cents).to eq(0)
    expect(result.lines.first.to_h.slice(:exempt, :exemption_reason, :base_cents))
      .to eq(exempt: true, exemption_reason: "Live performance, venue under 1,500 seats", base_cents: 2_000)
  end

  it "lets the most specific rule win: tier, listing, production, venue, then the org" do
    default_rule(rate(10.25))
    org.tax_rules.create!(money_kind: "tickets", applies_to: listing.production, exempt: true, exemption_reason: "Benefit night")
    expect(described_class.for_ticket(listing, tier, 2_000).tax_cents).to eq(0)

    org.tax_rules.create!(money_kind: "tickets", applies_to: tier, tax_rate_ids: [ rate(5).id ])
    expect(described_class.for_ticket(listing, tier, 2_000).tax_cents).to eq(100)
  end

  it "keeps course rules apart from ticket rules" do
    org.tax_rules.create!(money_kind: "courses", tax_rate_ids: [ rate(6.25).id ])
    expect(described_class.for_ticket(listing, tier, 2_000)).to eq(TaxCalculator::NONE)
  end

  it "won't let a rule name another organization's rate" do
    theirs = create(:organization).tax_rates.create!(name: "Theirs", rate_bps: 500)
    rule = org.tax_rules.build(money_kind: "tickets", tax_rate_ids: [ theirs.id ])
    expect(rule).not_to be_valid
  end
end

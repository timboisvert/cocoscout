# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract, "#deal_summary" do
  def contract_with(structure:, config:)
    build(:contract, draft_data: { "payment_structure" => structure, "payment_config" => config })
  end

  def values_for(contract)
    contract.deal_summary.map { |l| l[:value] }.join(" | ")
  end

  it "spells out a revenue share with split, guarantee, and settlement" do
    c = contract_with(structure: "revenue_share", config: {
      "who_sells_tickets" => "contractor", "settlement_basis" => "revenue_share",
      "revenue_source" => "ticket_sales", "revenue_our_share" => "40", "revenue_their_share" => "60",
      "revenue_guarantee" => "true", "revenue_guarantee_amount" => "500",
      "revenue_settlement" => "weekly"
    })

    summary = values_for(c)
    expect(summary).to include("They do")
    expect(summary).to include("we keep 40%, they keep 60%")
    expect(summary).to include("at least $500.00")
    expect(summary).to include("Settled weekly")
  end

  it "spells out a flat fee with a deposit" do
    c = contract_with(structure: "flat_fee", config: {
      "who_sells_tickets" => "org", "settlement_basis" => "flat",
      "flat_fee_direction" => "incoming", "flat_fee_amount" => "1000",
      "flat_fee_has_deposit" => "true", "flat_fee_deposit_percent" => "25"
    })

    summary = values_for(c)
    expect(summary).to include("We do")
    expect(summary).to include("Flat fee of $1000.00 — they pay us")
    expect(summary).to include("25% upfront")
  end

  it "describes ticket-revenue-minus-fee" do
    c = contract_with(structure: "flat_fee", config: {
      "who_sells_tickets" => "org", "settlement_basis" => "revenue_minus_fee",
      "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => "200"
    })

    expect(values_for(c)).to include("less our $200.00 fee")
  end

  it "spells out per-event terms" do
    c = contract_with(structure: "per_event", config: {
      "who_sells_tickets" => nil, "settlement_basis" => "flat",
      "per_event_direction" => "incoming", "per_event_amount" => "300",
      "per_event_timing" => "per_event"
    })

    summary = values_for(c)
    expect(summary).to include("No tickets on this deal")
    expect(summary).to include("$300.00 per event — they pay us")
  end

  it "always lists how they may pay us" do
    c = contract_with(structure: "flat_fee", config: {
      "flat_fee_direction" => "incoming", "flat_fee_amount" => "100",
      "accepted_payment_methods" => %w[online check]
    })

    pay_line = c.deal_summary.find { |l| l[:label] == "They may pay us by" }
    expect(pay_line[:value]).to include("online")
    expect(pay_line[:value]).to include("check")
  end
end

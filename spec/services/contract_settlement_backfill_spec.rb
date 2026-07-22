# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractSettlementBackfill do
  let(:org) { create(:organization) }

  def legacy_contract(structure:, config: {})
    create(:contract, organization: org,
                      draft_data: { "payment_structure" => structure, "payment_config" => config })
  end

  it "backfills settlement_basis and reconciles who-sells from existing payment direction" do
    c = legacy_contract(structure: "revenue_share", config: { "revenue_our_share" => 30 })
    create(:contract_payment, contract: c, direction: "outgoing", due_date: Date.current) # we pay them → we sell

    result = described_class.run
    c.reload

    expect(result.migrated).to eq(1)
    expect(c.draft_payment_config["settlement_basis"]).to eq("revenue_share")
    expect(c.draft_payment_config["who_sells_tickets"]).to eq("org")
    expect(c.settlement_direction).to eq("outgoing")
  end

  it "infers contractor-sells when existing payments are incoming" do
    c = legacy_contract(structure: "revenue_share", config: { "revenue_our_share" => 30 })
    create(:contract_payment, contract: c, direction: "incoming", due_date: Date.current)

    described_class.run
    expect(c.reload.draft_payment_config["who_sells_tickets"]).to eq("contractor")
  end

  it "maps ticket_revenue_minus_fee → revenue_minus_fee / we-sell" do
    c = legacy_contract(structure: "flat_fee",
                        config: { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 500 })
    described_class.run
    cfg = c.reload.draft_payment_config
    expect(cfg["settlement_basis"]).to eq("revenue_minus_fee")
    expect(cfg["who_sells_tickets"]).to eq("org")
  end

  it "is idempotent — skips contracts already carrying settlement_basis" do
    legacy_contract(structure: "revenue_share", config: { "settlement_basis" => "revenue_share" })
    result = described_class.run
    expect(result.migrated).to eq(0)
    expect(result.skipped).to eq(1)
  end

  it "dry run reports without writing" do
    c = legacy_contract(structure: "revenue_share", config: { "revenue_our_share" => 30 })
    result = described_class.run(dry_run: true)
    expect(result.migrated).to eq(1)
    expect(c.reload.draft_payment_config["settlement_basis"]).to be_nil
  end

  it "reports a mismatch when a flat contract's payments disagree with the derived direction" do
    c = legacy_contract(structure: "flat_fee", config: { "flat_fee_direction" => "incoming", "flat_fee_amount" => 100 })
    create(:contract_payment, contract: c, direction: "outgoing", due_date: Date.current) # contradicts incoming

    result = described_class.run
    expect(result.mismatches.map { |m| m[:contract_id] }).to include(c.id)
  end
end

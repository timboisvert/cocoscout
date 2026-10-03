# frozen_string_literal: true

require "rails_helper"

# One contract, two kinds of money: a revenue share on the shows, and a flat
# fee for each rehearsal that comes out of their ticket share (Improvised
# Animorphs). Before this they needed two contracts, so the rehearsal money
# couldn't be netted against the shows.
RSpec.describe "Contract rates for non-ticketed events", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:shows) { [ Time.zone.parse("2026-10-10 19:00"), Time.zone.parse("2026-10-17 19:00") ] }
  let(:rehearsals) { [ Time.zone.parse("2026-10-07 18:00"), Time.zone.parse("2026-10-14 18:00") ] }
  let(:rehearsal_rate) do
    { "event_type" => "rehearsal", "unit" => "per_event", "amount" => 50.0,
      "direction" => "incoming", "settlement" => "payout_deduction" }
  end

  def booking(time, type)
    { "location_id" => location.id, "starts_at" => time.iso8601, "ends_at" => (time + 3.hours).iso8601, "event_type" => type }
  end

  # We sell the tickets and pay them 70% monthly — money flows their way, so a
  # rehearsal fee can come out of it.
  def build_contract(event_rates: [ rehearsal_rate ])
    create(:contract, organization: org, contractor_name: "Improvised Animorphs",
                      contract_start_date: rehearsals.first.to_date, contract_end_date: shows.last.to_date,
                      draft_data: {
                        "bookings" => shows.map { |t| booking(t, "show") } + rehearsals.map { |t| booking(t, "rehearsal") },
                        "payments" => [ { "description" => "October revenue share", "amount" => 0, "amount_tbd" => true,
                                          "direction" => "outgoing", "due_date" => "2026-10-31" } ],
                        "payment_structure" => "revenue_share",
                        "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                                              "revenue_our_share" => 30, "revenue_settlement" => "monthly",
                                              "event_rates" => event_rates }
                      })
  end

  it "bills each rehearsal at its rate, to be taken out of their share, and keeps rehearsals out of the deal" do
    contract = build_contract
    contract.activate!

    fees = contract.contract_payments.where("description LIKE 'Rehearsal — %'").order(:due_date)
    expect(fees.map { |p| [ p.description, p.amount.to_f, p.direction, p.settlement_method ] }).to eq([
      [ "Rehearsal — Oct 7, 2026", 50.0, "incoming", "payout_deduction" ],
      [ "Rehearsal — Oct 14, 2026", 50.0, "incoming", "payout_deduction" ]
    ])
    expect(fees.map { |p| p.show.event_type }).to eq(%w[rehearsal rehearsal])
    expect(fees).to all(be_deduct_from_payout)

    # The deal sees the two shows, not the rehearsals.
    expect(contract.money_shows.map(&:event_type)).to eq(%w[show show])
    expect(contract.revenue_share_summary[:pending_count]).to eq(2)
    expect(contract.send(:deal_terms_html)).to include("Rehearsals:").and include("taken out of their ticket share")
  end

  it "bills directly when asked — its own payment on each rehearsal's date" do
    contract = build_contract(event_rates: [ rehearsal_rate.merge("settlement" => "direct", "unit" => "hourly", "amount" => 20.0) ])
    contract.activate!

    fees = contract.contract_payments.where("description LIKE 'Rehearsal — %'").order(:due_date)
    expect(fees.map { |p| [ p.amount.to_f, p.settlement_method, p.due_date.to_s ] })
      .to eq([ [ 60.0, "direct", "2026-10-07" ], [ 60.0, "direct", "2026-10-14" ] ]) # 3h × $20
  end

  it "leaves a contract without rates exactly as before — rehearsals are part of the deal" do
    contract = build_contract(event_rates: [])
    contract.activate!

    expect(contract.contract_payments.where("description LIKE 'Rehearsal — %'")).to be_empty
    expect(contract.money_shows.size).to eq(4)
  end

  it "re-bills pending rehearsal fees when the rate is amended, and leaves settled ones alone" do
    contract = build_contract
    contract.activate!
    settled = contract.contract_payments.find_by(description: "Rehearsal — Oct 7, 2026")
    settled.update_columns(status: "paid")

    config = contract.draft_payment_config.merge("event_rates" => [ rehearsal_rate.merge("amount" => 60.0) ])
    contract.apply_amendment!({ "payment_config" => config })

    fees = contract.contract_payments.where("description LIKE 'Rehearsal — %'").where.not(status: "cancelled").order(:due_date)
    expect(fees.map { |p| [ p.due_date.to_s, p.amount.to_f, p.status ] })
      .to eq([ [ "2026-10-07", 50.0, "paid" ], [ "2026-10-14", 60.0, "pending" ] ])
  end

  it "drops the fees when the rate is taken away" do
    contract = build_contract
    contract.activate!

    contract.apply_amendment!({ "payment_config" => contract.draft_payment_config.merge("event_rates" => []) })
    expect(contract.contract_payments.where("description LIKE 'Rehearsal — %'")).to be_empty
    expect(contract.reload.money_shows.size).to eq(4) # back in the deal
  end

  context "after a thin share only partly covered a rehearsal fee" do
    # Their October share came to $20 against $100 of rehearsal fees: it covers
    # $20 of the Oct 7 fee, and the $30 left of it carries as a running balance.
    let(:contractor) do
      create(:contractor, organization: org, name: "Improvised Animorphs").tap do |c|
        person = create(:person, stripe_account_id: "acct_ia", payouts_enabled: true)
        org.people << person
        c.update!(person: person)
      end
    end

    def offset_thin_share!(contract)
      share = contract.contract_payments.find_by(description: "October revenue share")
      share.update!(amount: 20, amount_tbd: false)
      ContractorPayoutRunService.add_contract_payment!(share)
    end

    def rehearsal_rows(contract)
      contract.contract_payments.where("description LIKE 'Rehearsal%'").where.not(status: "cancelled")
              .order(:due_date, :id).map { |p| [ p.description, p.amount.to_f, p.status, p.settlement_method ] }
    end

    let(:contract) do
      build_contract.tap do |c|
        c.update!(contractor: contractor)
        c.activate!
        offset_thin_share!(c)
      end
    end

    it "carries the uncovered part as a balance still taken out of their next share" do
      expect(rehearsal_rows(contract)).to eq([
        [ "Rehearsal — Oct 7, 2026", 20.0, "paid", "payout_deduction" ],
        [ "Rehearsal balance — Oct 7, 2026", 30.0, "pending", "payout_deduction" ],
        [ "Rehearsal — Oct 14, 2026", 50.0, "pending", "payout_deduction" ]
      ])
      balance = contract.contract_payments.find_by(description: "Rehearsal balance — Oct 7, 2026")
      expect(balance).to be_deduct_from_payout
      expect(balance).not_to be_collectable_online
      expect(balance.show.event_type).to eq("rehearsal")
    end

    it "never re-bills the part-paid rehearsal or drops its balance when the rate is amended" do
      contract # offset first
      config = contract.draft_payment_config.merge("event_rates" => [ rehearsal_rate.merge("amount" => 60.0) ])
      contract.apply_amendment!({ "payment_config" => config })

      expect(rehearsal_rows(contract)).to eq([
        [ "Rehearsal — Oct 7, 2026", 20.0, "paid", "payout_deduction" ],
        [ "Rehearsal balance — Oct 7, 2026", 30.0, "pending", "payout_deduction" ],
        [ "Rehearsal — Oct 14, 2026", 60.0, "pending", "payout_deduction" ] # untouched by any share: re-priced
      ])
    end

    it "keeps the balance through an amendment that also restages the payments" do
      contract # offset first
      contract.apply_amendment!({ "payment_config" => contract.draft_payment_config, "payments" => contract.draft_payments })

      expect(rehearsal_rows(contract)).to include([ "Rehearsal balance — Oct 7, 2026", 30.0, "pending", "payout_deduction" ])
      expect(rehearsal_rows(contract).count { |row| row.first == "Rehearsal — Oct 7, 2026" }).to eq(1)
    end

    it "never re-bills a rehearsal left in the old offset shape either" do
      # Before running balances, the remainder was rewritten in place and
      # flipped to direct — and an amendment then destroyed it and billed the
      # rehearsal again at the full rate.
      contract = build_contract.tap(&:activate!)
      legacy = contract.contract_payments.find_by(description: "Rehearsal — Oct 7, 2026")
      legacy.update!(amount: 30, settlement_method: "direct",
                     description: "Rehearsal — Oct 7, 2026 ($20.00 offset against payout)")

      config = contract.draft_payment_config.merge("event_rates" => [ rehearsal_rate.merge("amount" => 60.0) ])
      contract.apply_amendment!({ "payment_config" => config })

      expect(rehearsal_rows(contract)).to eq([
        [ "Rehearsal — Oct 7, 2026 ($20.00 offset against payout)", 30.0, "pending", "direct" ],
        [ "Rehearsal — Oct 14, 2026", 60.0, "pending", "payout_deduction" ]
      ])
    end
  end

  describe ".normalize_event_rates" do
    it "keeps only non-ticketed types with a rate of their own" do
      rates = Contract.normalize_event_rates(
        "rehearsal" => { "mode" => "own", "event_type" => "rehearsal", "amount" => "$50", "direction" => "incoming",
                         "unit" => "per_event", "settlement" => "payout_deduction" },
        "meeting" => { "mode" => "deal", "event_type" => "meeting", "amount" => "25" },
        "show" => { "mode" => "own", "event_type" => "show", "amount" => "100" }
      )
      expect(rates).to eq([ rehearsal_rate ])
    end

    it "never deducts money we owe them" do
      rates = Contract.normalize_event_rates([ { "event_type" => "rehearsal", "amount" => "40",
                                                  "direction" => "outgoing", "settlement" => "payout_deduction" } ])
      expect(rates.first["settlement"]).to eq("direct")
    end
  end
end

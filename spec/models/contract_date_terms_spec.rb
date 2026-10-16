# frozen_string_literal: true

require "rails_helper"

# Each date's own terms (Review the dates, 2026-10-16): the deal sets what
# every date gets, one date can differ, down to $0, and billing and settlement
# follow the date once it's a show.
RSpec.describe "Contract date terms", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:show_times) { [ Time.zone.parse("2026-10-10 19:00"), Time.zone.parse("2026-10-17 19:00") ] }
  let(:rehearsal_times) { [ Time.zone.parse("2026-10-07 18:00"), Time.zone.parse("2026-10-14 18:00") ] }
  let(:rehearsal_rate) do
    { "event_type" => "rehearsal", "unit" => "per_event", "amount" => 50.0, "direction" => "incoming", "settlement" => "direct" }
  end

  def booking(time, type)
    { "location_id" => location.id, "starts_at" => time.iso8601, "ends_at" => (time + 3.hours).iso8601, "event_type" => type }
  end

  def revenue_share_contract
    create(:contract, organization: org, contractor_name: "Improvised Animorphs",
                      contract_start_date: rehearsal_times.first.to_date, contract_end_date: show_times.last.to_date,
                      draft_data: {
                        "bookings" => show_times.map { |t| booking(t, "show") } + rehearsal_times.map { |t| booking(t, "rehearsal") },
                        "payments" => [ { "description" => "October revenue share", "amount" => 0, "amount_tbd" => true,
                                          "direction" => "outgoing", "due_date" => "2026-10-31" } ],
                        "payment_structure" => "revenue_share",
                        "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                                              "revenue_our_share" => 30, "revenue_settlement" => "monthly",
                                              "event_rates" => [ rehearsal_rate ] }
                      })
  end

  it "knows what each kind of date can change, and what the deal gives it" do
    contract = revenue_share_contract
    expect([ contract.date_term_field("rehearsal"), contract.usual_date_term("rehearsal") ]).to eq([ :amount, 50.0 ])
    expect([ contract.date_term_field("show"), contract.usual_date_term("show") ]).to eq([ :share, 30.0 ])
    expect(contract.date_terms_words("show", {})).to eq([ "Revenue share", "30% of ticket sales to us", false ])
    expect(contract.date_terms_words("rehearsal", { "amount" => 0.0 })).to eq([ "$0 this rehearsal", "Usually $50 per rehearsal", true ])
  end

  it "keeps a date's own terms, drops ones back to the deal, and stamps them on the shows" do
    contract = revenue_share_contract
    free, paid = rehearsal_times.map(&:iso8601)
    contract.set_draft_date_terms!([ free ], value: "0", note: "Tech rehearsal, included", field: :amount)
    contract.set_draft_date_terms!([ paid ], value: "50", note: "", field: :amount) # the deal's own rate: nothing kept
    contract.set_draft_date_terms!([ show_times.first.iso8601 ], value: "0", note: nil, field: :share)
    contract.set_draft_date_terms!([ show_times.first.iso8601 ], value: "", note: nil, field: :amount) # wrong kind: ignored

    expect(contract.reload.draft_date_terms).to eq(
      free => { "amount" => 0.0, "note" => "Tech rehearsal, included" },
      show_times.first.iso8601 => { "share" => 0.0 }
    )

    # Financials saves again: the dates keep their terms.
    contract.update_draft_step(:payment_config, contract.draft_payment_config.merge("revenue_our_share" => 30))
    contract.activate!

    fees = contract.contract_payments.where("description LIKE 'Rehearsal — %'").order(:due_date)
    expect(fees.map { |p| [ p.description, p.amount.to_f ] }).to eq([ [ "Rehearsal — Oct 14, 2026", 50.0 ] ]) # Oct 7 is $0
    rehearsal = contract.contract_shows.find_by(date_and_time: rehearsal_times.first)
    expect(rehearsal.contract_terms).to eq("amount" => 0.0, "note" => "Tech rehearsal, included")

    # Settlement, show by show: the first show is 0% to us, so they keep it all.
    first, second = show_times.map { |t| contract.contract_shows.find_by(date_and_time: t) }
    [ first, second ].each { |show| create(:show_financials, show: show, ticket_revenue: 1_000) }
    [ first, second ].each(&:reload)
    expect(first.show_financials.total_revenue).to eq(1_000)
    expect(contract.our_share_for(first)).to eq(0.0)
    expect(contract.settled_share_amount([ first, second ])).to eq(1_700.0) # theirs: 100% + 70%
  end

  it "prices a per-show fee by each show's own" do
    contract = create(:contract, :active, organization: org, draft_data: {
      "payment_structure" => "flat_fee",
      "payment_config" => { "settlement_basis" => "revenue_minus_fee", "flat_fee_direction" => "ticket_revenue_minus_fee",
                            "flat_fee_amount" => 300, "flat_fee_basis" => "per_show" }
    })
    expect(contract.date_term_field("show")).to eq(:amount)
    shows = [ build(:show, contract_terms: { "amount" => 0.0 }), build(:show) ]
    expect(contract.flat_fee_for_shows(shows)).to eq(300.0)
    expect(contract.flat_fee_for_shows(2)).to eq(600.0)
  end

  it "has nothing to change per date on a whole-contract flat fee" do
    contract = create(:contract, organization: org, draft_data: { "payment_structure" => "flat_fee",
                                                                  "payment_config" => { "settlement_basis" => "flat", "flat_fee_amount" => 2_000 } })
    expect(contract.date_term_field("show")).to be_nil
    expect(contract.date_terms_words("show", {}).first(2)).to eq([ "Flat fee", "Part of the $2,000 fee" ])
  end

  it "gives a per-event deal's date its own fee, and a $0 date no payment" do
    times = show_times.map(&:iso8601)
    contract = create(:contract, organization: org, draft_data: {
      "bookings" => show_times.map { |t| booking(t, "show") },
      "payment_structure" => "per_event",
      "payment_config" => { "settlement_basis" => "flat", "per_event_amount" => 200 },
      "payments" => show_times.map { |t| { "description" => "#{t.strftime('%b %-d')} event", "amount" => 200, "direction" => "incoming", "due_date" => t.to_date.to_s } }
    })
    contract.set_draft_date_terms!([ times.first ], value: "0", note: nil, field: :amount)
    contract.set_draft_date_terms!([ times.last ], value: "150", note: nil, field: :amount)

    expect(contract.reload.billed_draft_payments.map { |p| [ p["due_date"], p["amount"] ] }).to eq([ [ show_times.last.to_date.to_s, 150.0 ] ])
    expect(contract.draft_payments.size).to eq(2) # the deal's own list is never rewritten

    # Back to the deal's fee: its payment is back too.
    contract.set_draft_date_terms!([ times.first ], value: "200", note: nil, field: :amount)
    expect(contract.reload.billed_draft_payments.map { |p| p["amount"] }).to eq([ 200, 150.0 ])

    # Activation bills the dates as they stand.
    contract.set_draft_date_terms!([ times.first ], value: "0", note: nil, field: :amount)
    contract.update!(contract_start_date: show_times.first.to_date, contract_end_date: show_times.last.to_date)
    contract.reload.activate!
    expect(contract.contract_payments.map { |p| p.amount.to_f }).to eq([ 150.0 ])
  end

  it "matches a date's payment by the date it's for, when it's due days before" do
    contract = create(:contract, organization: org, draft_data: {
      "bookings" => show_times.map { |t| booking(t, "show") },
      "payment_structure" => "per_event",
      "payment_config" => { "settlement_basis" => "flat", "per_event_amount" => 200, "per_event_terms" => "before" },
      "payments" => show_times.map { |t| { "description" => "#{t.strftime('%b %-d')} event", "amount" => 200, "direction" => "incoming", "source" => "Per event",
                                           "due_date" => (t.to_date - 7).to_s, "event_date" => t.iso8601 } }
    })
    contract.set_draft_date_terms!([ show_times.first.iso8601 ], value: "50", note: nil, field: :amount)
    expect(contract.reload.billed_draft_payments.map { |p| p["amount"] }).to eq([ 50.0, 200 ])
  end

  it "adds the dates up on one upfront payment" do
    contract = create(:contract, organization: org, draft_data: {
      "bookings" => show_times.map { |t| booking(t, "show") },
      "payment_structure" => "per_event",
      "payment_config" => { "settlement_basis" => "flat", "per_event_amount" => 200, "per_event_timing" => "upfront" },
      "payments" => [ { "description" => "2 events @ $200.00 each, paid upfront", "amount" => 400, "direction" => "incoming", "source" => "Per event",
                        "due_date" => "2026-10-01" } ]
    })
    contract.set_draft_date_terms!([ show_times.first.iso8601 ], value: "0", note: nil, field: :amount)
    expect(contract.reload.billed_draft_payments).to eq([ { "description" => "2 events, paid upfront", "amount" => 200.0, "direction" => "incoming",
                                                            "source" => "Per event", "due_date" => "2026-10-01" } ])
  end
end

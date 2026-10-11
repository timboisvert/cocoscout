# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ShowPayouts contract shows", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:show) { create(:show, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def payable_person
    p = create(:person)
    p.update!(stripe_account_id: "acct_p#{p.id}", payouts_enabled: true)
    p
  end

  it "shows the contract payout (not the casting flow) with a pay action for an owed payment" do
    person = payable_person
    contractor = create(:contractor, organization: org, person: person, name: "Lighting Co")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    create(:contract_payment, contract: contract, show: show, direction: "outgoing",
                              status: "pending", amount: 500, due_date: Date.current)

    get manage_money_show_payout_path(show)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contract payments for this show")
    expect(response.body).to include("Lighting Co")
    expect(response.body).to include("Add to payout run")
    # Not the casting flow.
    expect(response.body).not_to include("Calculate Payout")
  end

  it "settles a per-event rental on its contract rather than offering a payout scheme" do
    # A per-event fee deal never writes show_id onto its payments, so the show
    # has to be recognized by the contract that booked it.
    contractor = create(:contractor, organization: org, person: create(:person), name: "Tommy Corts")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name,
                                           draft_data: {
                                             "payment_structure" => "per_event",
                                             "payment_config" => { "per_event_amount" => "300", "per_event_direction" => "incoming" }
                                           })
    rental = create(:space_rental, contract: contract, starts_at: show.date_and_time)
    show.update!(space_rental: rental)
    create(:contract_payment, contract: contract, direction: "incoming", status: "pending",
                              amount: 300, due_date: show.date_and_time.to_date, description: "Event 2 Fee")

    get manage_money_show_payout_path(show)

    expect(response.body).to include("Contract payments for this show")
    expect(response.body).to include("Event 2 Fee")
    expect(response.body).not_to include("Payout Scheme")
  end

  it "offers the run for a contractor whose person hasn't connected a bank yet" do
    contractor = create(:contractor, organization: org, person: create(:person), name: "No Bank Co")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    create(:contract_payment, contract: contract, show: show, direction: "outgoing",
                              status: "pending", amount: 500, due_date: Date.current)

    get manage_money_show_payout_path(show)

    expect(response.body).to include("Contract payments for this show")
    expect(response.body).to include("Add to payout run")
    expect(response.body).not_to include("Needs a person")
  end

  it "flags a contractor with no person behind it instead of offering to pay" do
    contractor = create(:contractor, organization: org, person: nil, name: "Nobody Co")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    create(:contract_payment, contract: contract, show: show, direction: "outgoing",
                              status: "pending", amount: 500, due_date: Date.current)

    get manage_money_show_payout_path(show)

    expect(response.body).to include("Contract payments for this show")
    expect(response.body).to include("Needs a person")
    expect(response.body).not_to include("Add to payout run")
  end

  # Tim, 2026-10-10: the show's payout page listed Booth Tech as "Expected
  # income · Collect this payment" while the contract page had it taken out of
  # their share. Both pages draw the same rows now.
  it "draws the contract page's rows: a charge taken out of their share, never one to collect" do
    contractor = create(:contractor, organization: org, person: payable_person, name: "Windy City Witches")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    day = show.date_and_time.to_date
    create(:contract_payment, contract: contract, show: show, direction: "outgoing", status: "pending", amount: 395,
                              description: "Ticket revenue less $300.00 fee — #{day.strftime('%b %-d, %Y')}", due_date: day)
    create(:contract_payment, contract: contract, show: show, direction: "incoming", status: "pending", amount: 50,
                              description: "Booth Tech — #{day.strftime('%b %-d, %Y')}", settlement_method: "payout_deduction", due_date: day)

    get manage_money_show_payout_path(show)
    html = response.body.gsub(/\s+/, " ")

    expect(html).to include("Taken out of their share", "Booth Tech", "−$50.00", "Add to payout run")
    expect(html).to match(%r{We pay them</dt> <dd[^>]*> \$345\.00 </dd>})
    expect(html).to match(%r{Still to pay for this show</div> <div[^>]*>\$345\.00</div>})
    expect(html).not_to include("Expected income", "Collect this payment", "Still owed to you")
  end

  # Contract 116 as it really was (Tim, 2026-10-11): the settlement matched to
  # the night by its date, not linked; Booth Tech linked to the show; the
  # settlement already on a payout run. The page showed Booth Tech alone and
  # "Ready to Calculate". It shows the working: $695 sold, our $300 fee,
  # Booth Tech $50, $345 to them.
  it "shows a minus-fee night's settlement and its working, however the settlement is linked" do
    travel_to Time.zone.local(2026, 10, 12, 12) do
      contractor = create(:contractor, organization: org, person: payable_person, name: "Windy City Witches")
      contract = create(:contract, :active, organization: org, production: production, contractor: contractor,
                                             contractor_name: contractor.name, draft_data: {
                                               "payment_structure" => "flat_fee",
                                               "payment_config" => { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 300,
                                                                     "flat_fee_basis" => "per_show", "flat_fee_settlement" => "per_event" }
                                             })
      night = Time.zone.local(2026, 10, 11, 17)
      rental = create(:space_rental, contract: contract, starts_at: night)
      witches = create(:show, production: production, space_rental: rental, date_and_time: night)
      create(:show_financials, show: witches, ticket_revenue: 695, data_confirmed: true)
      settlement = create(:contract_payment, contract: contract, direction: "outgoing", amount: 395, amount_tbd: false,
                                             description: "Ticket revenue less $300.00 fee — Oct 11, 2026", due_date: night.to_date,
                                             notes: "Auto-calculated from show financials:")
      create(:contract_payment, contract: contract, show: witches, direction: "incoming", amount: 50,
                                description: "Booth Tech — Oct 11, 2026", settlement_method: "payout_deduction", due_date: night.to_date)
      settlement.update_column(:show_id, nil)
      ContractorPayoutRunService.add_contract_payment!(settlement)

      get manage_money_show_payout_path(witches)
      html = response.body.gsub(/\s+/, " ")

      expect(html).to match(%r{Ticket sales — Oct 11</dt> <dd[^>]*> \$695\.00 </dd>})
      expect(html).to match(%r{Our fee</dt> <dd[^>]*> −\$300\.00 </dd>})
      expect(html).to include("Taken out of their share", "Booth Tech — Oct 11, 2026", "−$50.00")
      expect(html).to match(%r{We pay them</dt> <dd[^>]*> \$345\.00 </dd>})
      expect(html).to include("In payout run", "In a payout run", "Settled on the contract with Windy City Witches")
      expect(html).to match(%r{Still to pay for this show</div> <div[^>]*>\$345\.00</div>})
      expect(html).not_to include("Ready to Calculate", "(they pay us)", "overdue")

      # Money → Payouts counts the same $345 for it, not $395.
      get manage_money_payouts_path
      expect(response.body).to include("$345.00")
      expect(response.body).not_to include("$395.00")
    end
  end
end

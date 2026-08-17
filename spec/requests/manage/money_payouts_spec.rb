# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::MoneyPayouts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Payout Prod") }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 150) }
  # $70 paid + $50 + $30 unpaid → $80 still awaiting.
  let!(:li_paid) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 70) }
  let!(:li_a) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 50) }
  let!(:li_b) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 30) }

  before do
    li_paid.update_columns(manually_paid: true, manually_paid_at: Time.current)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "lists the show under Awaiting Payout with the remaining amount, not the full total" do
    get manage_money_production_payouts_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Awaiting Payout").and include("All Shows")
    expect(response.body).to include("$80.00")     # remaining unpaid, not the full $150
    expect(response.body).to include("1 of 3 paid")
  end

  it "keeps the org page action-focused: Awaiting Payout plus a link to All payouts" do
    get manage_money_payouts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Awaiting Payout")
    expect(response.body).to include("Payout Prod")
    expect(response.body).to include("$80.00") # remaining awaiting
    # Breadcrumb back to the money hub (like the financials page).
    expect(response.body).to include(manage_money_index_path)
    # The full grid moved to its own page.
    expect(response.body).to include(manage_money_all_payouts_path)
  end

  it "shows the every-production accordion on the All Payouts page" do
    get manage_money_all_payouts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payout Prod")
    # Rows expand to a lazy payout-events frame.
    expect(response.body).to include("payout-events-#{production.id}")
    expect(response.body).to include(manage_money_production_payout_events_path(production))
  end

  it "sends a single-awaiting-show item straight to that show's payout (not the production page)" do
    get manage_money_payouts_path
    # Only one show is awaiting → the Awaiting item is a direct shortcut to it.
    expect(response.body).to include(manage_money_show_payout_path(show))
    expect(response.body).not_to include("awaiting-events-#{production.id}")
  end

  context "with several shows awaiting in one production" do
    let!(:show2) { create(:show, production: production, event_type: :show, date_and_time: 5.days.ago) }
    let!(:payout2) { ShowPayout.create!(show: show2, status: "awaiting_payout", calculated_at: Time.current, total_payout: 40) }
    let!(:li2) { ShowPayoutLineItem.create!(show_payout: payout2, payee: create(:person), amount: 40) }

    it "shows an accordion of the awaiting shows instead of a direct link" do
      get manage_money_payouts_path
      expect(response.body).to include("awaiting-events-#{production.id}")
      expect(response.body).to include(manage_money_production_payout_events_path(production, awaiting: 1))
    end

    it "the awaiting accordion lists only shows that still owe someone" do
      get manage_money_production_payout_events_path(production, awaiting: 1),
          headers: { "Turbo-Frame" => "awaiting-events-#{production.id}" }
      expect(response.body).to include("awaiting-events-#{production.id}")
      expect(response.body).to include(show.display_name).and include(show2.display_name)
      expect(response.body).to include(manage_money_show_payout_path(show))
      # No cols param → just the default To pay column; the paid amount ($70)
      # is not shown here.
      expect(response.body).to include("$80.00")
      expect(response.body).not_to include("$70.00")
    end

    it "the accordion mirrors the status columns the grid passes it" do
      get manage_money_production_payout_events_path(production, awaiting: 1, cols: "to_pay,paid"),
          headers: { "Turbo-Frame" => "awaiting-events-#{production.id}" }
      expect(response.body).to include("$80.00").and include("$70.00")
    end
  end

  context "with money staged in a payout run" do
    let!(:batch) { PayoutBatch.create!(organization: org, kind: "performer", status: "draft", trigger: "manual") }
    let!(:batch_item) { batch.items.create!(payee: li_a.payee, amount_cents: 5000, status: "pending") }
    let!(:contribution) do
      batch_item.payout_contributions.create!(payout_batch: batch, payee: li_a.payee, label: "Show pay",
                                              amount_cents: 5000, source: li_a)
    end

    it "splits the awaiting grid into To pay / In draft run / Paid columns" do
      get manage_money_payouts_path
      expect(response.body).to include("To pay").and include("In draft run").and include("Paid")
      expect(response.body).to include("$30.00") # li_b — still needs action
      expect(response.body).to include("$50.00") # li_a — staged, run not yet submitted
      expect(response.body).to include("$70.00") # li_paid — already paid
      expect(response.body).to include("1 payee to pay · 1 in a draft run · 1 already paid")
    end

    it "moves the staged money to In flight once the run is submitted" do
      batch.update!(status: "funding")
      get manage_money_payouts_path
      expect(response.body).to include("In flight")
      expect(response.body).not_to include("In draft run")
    end

    it "shows the state boxes summing the same money as the sections below" do
      get manage_money_payouts_path
      expect(response.body).to include("To pay").and include("In draft")
        .and include("Funding").and include("Waiting on payees")
      expect(response.body).to include("$30.00") # to pay — li_b, not in any run
      expect(response.body).to include("$50.00") # in draft — the staged batch
    end

    it "lists the draft run under Active Runs" do
      get manage_money_payouts_path
      expect(response.body).to include("Active Runs")
      expect(response.body).to include("Not submitted")
      expect(response.body).to include(manage_payout_batch_path(batch))
    end

    it "puts a partially paid run's unpaid remainder in the Waiting on payees box" do
      batch.update!(status: "partially_paid")
      batch.items.create!(payee: create(:person), amount_cents: 2000, status: "paid")
      batch.recalculate_total!
      get manage_money_payouts_path
      # $70 run total, $20 paid → $50 still waiting on payees — the run row
      # says who it's stuck on, and the Waiting on bank column carries the amount.
      expect(response.body).to include("Waiting on bank")
      expect(response.body).to include("1 payee waiting on bank info")
      expect(response.body).to include("$50.00")
    end
  end

  it "renders the lazy payout-events frame with per-show awaiting/paid" do
    get manage_money_production_payout_events_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("payout-events-#{production.id}")
    expect(response.body).to include(show.display_name)
    expect(response.body).to include(manage_money_show_payout_path(show))
    expect(response.body).to include("$80.00").and include("$70.00") # awaiting / paid
    expect(response.body).to include("1 of 3 paid")
  end
end

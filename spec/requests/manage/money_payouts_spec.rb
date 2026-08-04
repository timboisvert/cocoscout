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

    it "the awaiting accordion lists only shows that still owe someone, one column" do
      get manage_money_production_payout_events_path(production, awaiting: 1),
          headers: { "Turbo-Frame" => "awaiting-events-#{production.id}" }
      expect(response.body).to include("awaiting-events-#{production.id}")
      expect(response.body).to include(show.display_name).and include(show2.display_name)
      expect(response.body).to include(manage_money_show_payout_path(show))
      # Single "Awaiting" column — the paid amount ($70) is not shown here.
      expect(response.body).to include("$80.00")
      expect(response.body).not_to include("$70.00")
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

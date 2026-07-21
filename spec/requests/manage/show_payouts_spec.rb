# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ShowPayouts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 500) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 180) }
  let!(:li_paid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Paid Pat"), amount: 60)
      .tap { |li| li.update_columns(manually_paid: true) }
  end
  let!(:li_unpaid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Owed Ollie", stripe_account_id: "acct_1", payouts_enabled: true), amount: 120)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "shows the remaining amount to pay, not just the full total" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("$120.00 to pay")  # remaining, not $180
    expect(response.body).to include("$180.00 total")
    expect(response.body).to include("$60.00 paid")
  end

  it "offers an add-to-run preview modal instead of a confirm alert" do
    get manage_money_show_payout_path(show)
    expect(response.body).to include("add-to-run-modal")
    expect(response.body).to include("Owed Ollie")            # eligible unpaid performer listed
    expect(response.body).not_to include("turbo_confirm=\"Add these performer payouts")
  end

  it "stays on the payout page after adding to the run (doesn't jump to the batch)" do
    post manage_add_to_run_money_show_payout_path(show)
    expect(response).to redirect_to(manage_money_show_payout_path(show))
  end
end

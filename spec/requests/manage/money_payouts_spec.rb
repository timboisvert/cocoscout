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

  it "counts only the remaining unpaid line items as awaiting on the production page" do
    get manage_money_production_payouts_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("$80.00")      # remaining, not the full $150
    expect(response.body).to match(/2\s*people/)     # 2 still to pay
    expect(response.body).to match(/1\s*people/)     # 1 already paid
  end

  it "nets the org-wide awaiting total to the remaining amount" do
    get manage_money_payouts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("$80.00")
  end
end

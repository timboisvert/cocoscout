# frozen_string_literal: true

require "rails_helper"

# Settle up (Books V1.3): one worksheet per day that had money in it.
RSpec.describe "Settle up", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Halloween Show") }
  let!(:show) { create(:show, production: production, date_and_time: 2.days.ago.change(hour: 20)) }
  let(:date) { SettlementDay.day_for(org, show.date_and_time) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "lists the day to settle, shows its worksheet, checks the show, settles and reopens the day" do
    get manage_money_settle_up_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("To settle", "Halloween Show", "Settle up")

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(date.strftime("%A, %B %-d"), "Looks right", "0 of 1 checked")

    # Not every piece is checked: settling is refused.
    post manage_settle_money_settle_up_day_path(date.iso8601)
    expect(SettlementDay.find_by(organization: org, date: date)).to be_nil
    expect(flash[:alert]).to include("Check every piece")

    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    expect(show.reload.show_financials.data_confirmed).to be(true)

    post manage_settle_money_settle_up_day_path(date.iso8601)
    record = SettlementDay.find_by!(organization: org, date: date)
    expect(record).to be_settled
    expect(record.settled_by).to eq(owner)

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("is settled", "Reopen this day")

    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "A count was fixed later" }
    expect(record.reload).to be_open
    expect(record.reopen_reason).to eq("A count was fixed later")

    get manage_money_settle_up_path(filter: "all", month: date.strftime("%Y-%m"))
    expect(response.body).to include(date.strftime("%b %-d"))
  end

  it "counts the door cash, and puts an over or short on the books when the day settles" do
    patch manage_door_cash_money_settle_up_day_path(date.iso8601), params: { counted: "5.00", float_kept: "0", note: "Found a five in the box" }
    record = SettlementDay.find_by!(organization: org, date: date)
    expect(record.counted_cents).to eq(500)
    get manage_money_settle_up_day_path(date.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("over", "Found a five in the box")

    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    post manage_settle_money_settle_up_day_path(date.iso8601)
    expect(record.reload).to be_settled
    entry = JournalEntry.live.find_by(organization: org, source: record, kind: "settlement")
    expect(entry).to be_present
    expect(ChartOfAccounts.account(org, :other_income).natural_balance_cents).to eq(500)

    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Counted again" }
    expect(JournalEntry.live.where(organization: org, source: record, kind: "settlement")).not_to exist
    expect(ChartOfAccounts.account(org, :other_income).natural_balance_cents).to eq(0)
  end

  it "shows days to settle on the Money hub and on Home" do
    get manage_money_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1 day to settle up", "Days to settle")
    get manage_path
    expect(response.body).to include("1 day to settle up")
  end

  it "saves the when-a-day-ends setting" do
    patch manage_money_settings_settle_up_path, params: { settlement_day_mode: "calendar", settlement_day_starts_at: "5" }
    expect(org.reload.settlement_day_mode).to eq("calendar")
    expect(org.settlement_day_starts_at).to eq(5)
    get manage_money_settings_section_path(section: "settle_up")
    expect(response.body).to include("When a day ends", "At midnight")
  end
end

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

  it "steps between days with the picker Home has: earlier, the day, later, Today" do
    get manage_money_settle_up_day_path(date.iso8601)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-week-picker')
    expect(response.body).to include(date.strftime("%a, %b %-d, %Y"))
    expect(response.body).to match(/title="Earlier"[^>]*href="#{Regexp.escape(manage_money_settle_up_day_path((date - 1).iso8601))}"/)
    expect(response.body).to match(/title="Later"[^>]*href="#{Regexp.escape(manage_money_settle_up_day_path((date + 1).iso8601))}"/)
    expect(response.body).to include(%(href="#{manage_money_settle_up_day_path(SettlementDay.day_for(org, Time.current).iso8601)}")).and include(">Today<")
    expect(response.body).to include("Days with money")
    expect(response.body).not_to include("No earlier day")
  end

  it "opens a show's expenses and other revenue in their own modals, and saves each back onto the day" do
    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include(%(data-modal-id="expenses-#{show.id}")).and include(%(data-modal-id="other-revenue-#{show.id}"))
    expect(response.body).not_to include("Open the worksheet")

    fin = show.show_financials || show.create_show_financials!
    fin.update!(other_revenue_details: [ { "description" => TicketSalesSync::PRODUCTS_LABEL, "amount" => 40.0 } ])

    patch manage_update_money_show_financials_path(show), params: { return_to: manage_money_settle_up_day_path(date.iso8601),
      show_financials: { expense_items_cleared: "1", expense_items_attributes: {
        "0" => { category: ExpenseItem::CATEGORIES.first, description: "Pizza for the cast", amount: "42.50", _destroy: "0" },
        "1" => { category: ExpenseItem::CATEGORIES.first, description: "", amount: "", _destroy: "0" } } } }
    expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601))
    expect(fin.reload.expense_items.map { |i| [ i.description, i.amount.to_f ] }).to eq([ [ "Pizza for the cast", 42.5 ] ])

    patch manage_update_money_show_financials_path(show), params: { return_to: manage_money_settle_up_day_path(date.iso8601),
      show_financials: { other_revenue_details_cleared: "1", other_revenue_details: {
        "0" => { description: TicketSalesSync::PRODUCTS_LABEL, amount: "40.0" },
        "1" => { description: "Raffle", amount: "85", _destroy: "0" },
        "2" => { description: "", amount: "", _destroy: "0" },
        "3" => { description: "Sponsor", amount: "100", _destroy: "1" } } } }
    expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601))
    expect(fin.reload.normalized_other_revenue_details.map { |i| [ i["description"], i["amount"].to_f ] }).to contain_exactly([ TicketSalesSync::PRODUCTS_LABEL, 40.0 ], [ "Raffle", 85.0 ])

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("Pizza for the cast").and include("Raffle").and include("$42.50").and include("$85.00").and include("$40.00")

    patch manage_update_money_show_financials_path(show), params: { return_to: manage_money_settle_up_day_path(date.iso8601),
      show_financials: { expense_items_cleared: "1", expense_items_attributes: { "0" => { id: fin.expense_items.first.id, category: ExpenseItem::CATEGORIES.first, description: "Pizza", amount: "", _destroy: "0" } } } }
    expect(fin.reload.expense_items).to be_empty
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
    expect(response.body).to include("When a day starts and ends", "A day starts", "A day ends", "At midnight")
  end
end

# A register's day (Square, plan §9.3) on the worksheet: checked like any
# piece, posted to the books on settle, tips split to the payout run.
RSpec.describe "Manage::SettlementDays with a register", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "calendar") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:lodge) { create(:location, organization: org, name: "Lincoln Lodge") }
  let(:date) { Date.current - 2 }
  let!(:integration) { org.integrations.create!(provider: "square", tokens: { "access_token" => "tok" }, settings: { "locations" => [ { "id" => "L1", "name" => "The bar" } ], "location_map" => { "L1" => lodge.id.to_s } }) }
  let!(:register) do
    integration.register_days.create!(organization: org, location: lodge, external_location_id: "L1", business_date: date,
                                      sales_by_category: { "bar" => 10_000, "merchandise" => 2_000 }, gross_cents: 12_000, tips_cents: 1_500, tax_cents: 1_000,
                                      refunds_cents: 600, fees_cents: 330, net_cents: 12_000 + 1_000 + 1_500 - 600 - 330, orders_count: 40, pulled_at: Time.current)
  end
  let(:bartender) { create(:person, name: "Pat Bartender") }
  let!(:member) { org.organization_staff_members.create!(person: bartender) }
  let(:role) { org.house_roles.create!(name: "Bar") }

  before do
    org.shifts.create!(house_role: role, starts_at: date.in_time_zone.change(hour: 19), ends_at: date.in_time_zone.change(hour: 23)).shift_assignments.create!(person: bartender)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "lists a day with only register money, shows it on the worksheet, and settles it onto the books with the tips on the run" do
    get manage_money_settle_up_path
    expect(response.body).to include(manage_money_settle_up_day_path(date.iso8601), "Bar, Lincoln Lodge", "Tips")

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("Bar, Lincoln Lodge", "$100.00", "$20.00", "Sales tax collected", "Tips, $15.00", "Pat Bartender", "On its way to your bank")

    patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
    patch manage_tips_money_settle_up_day_path(date.iso8601), params: { split: "even", checked: "1", shares: { bartender.id => { amount: "15.00", method: "payout" } } }
    record = SettlementDay.find_by!(organization: org, date: date)
    expect(record.tip_shares.sum(:amount_cents)).to eq(1_500)

    post manage_settle_money_settle_up_day_path(date.iso8601)
    expect(record.reload).to be_settled
    expect(ChartOfAccounts.account(org, :bar_income).natural_balance_cents).to eq(10_000 - 500)
    expect(ChartOfAccounts.account(org, :merchandise_income).natural_balance_cents).to eq(2_000 - 100)
    expect(ChartOfAccounts.account(org, :tax_to_remit).natural_balance_cents).to eq(1_000)
    expect(ChartOfAccounts.account(org, :tips_owed).natural_balance_cents).to eq(1_500)
    expect(ChartOfAccounts.account(org, :ticketing_fees).natural_balance_cents).to eq(330)
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(12_000 + 1_000 + 1_500 - 600 - 330)
    share = record.tip_shares.first
    expect(share.payout_contribution).to be_present
    expect(share.payout_contribution.payout_batch).to be_open
    expect(share.payout_contribution.amount_cents).to eq(1_500)

    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Wrong split" }
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(0)
    expect(share.reload.payout_contribution).to be_nil
    expect(PayoutContribution.where(payee: bartender).count).to eq(0)
  end
end

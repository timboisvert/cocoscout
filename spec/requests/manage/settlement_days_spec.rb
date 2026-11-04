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
    # The calendar's dots say where a day stands, not just that it had money (Tim, 2026-11-03).
    expect(response.body).to include("Settled", "To settle", "Not over yet, or history")
    expect(response.body).to include(%(aria-label="#{date.strftime("%A, %B %-d")} · to settle"))
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
    # The share waits on Pay People with the approved hours; nothing goes on
    # the run until the week's pay is put there together (Tim, 2026-11-03).
    share = record.tip_shares.first
    expect(share.payout_contribution).to be_nil
    expect(TipShare.waiting_for(org)).to eq([ share ])
    expect(PayoutContribution.where(payee: bartender).count).to eq(0)

    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Wrong split" }
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(0)
    expect(TipShare.waiting_for(org)).to be_empty
  end
end

# Tips go to whoever was working (plan §9.14): the organization's rule, read
# against the register's tips by quarter hour and Staffing's shifts.
RSpec.describe "Manage::SettlementDays tips by the clock", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "calendar") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:lodge) { create(:location, organization: org, name: "Lincoln Lodge") }
  let(:date) { Date.current - 2 }
  let(:night) { date.in_time_zone }
  let!(:integration) { org.integrations.create!(provider: "square", tokens: { "access_token" => "tok" }, settings: { "locations" => [ { "id" => "L1", "name" => "The bar" } ], "location_map" => { "L1" => lodge.id.to_s } }) }
  # $10 of tips every quarter hour from 6 pm to midnight: $240. Clock times,
  # not offsets: the day may be the one the clocks fall back on.
  let(:by_time) { (18 * 4...24 * 4).to_h { |q| [ SquareSync.quarter_key(night.change(hour: q / 4, min: (q % 4) * 15)), { "cents" => 1_000, "orders" => 2 } ] } }
  let!(:register) do
    integration.register_days.create!(organization: org, location: lodge, external_location_id: "L1", business_date: date, sales_by_category: { "bar" => 100_000 }, gross_cents: 100_000,
                                      tips_cents: 24_000, tax_cents: 0, refunds_cents: 0, fees_cents: 0, net_cents: 124_000, orders_count: 48, pulled_at: Time.current, tips_by_time: by_time)
  end
  let(:bartender) { org.house_roles.create!(name: "Bartender") }
  let!(:bar_back) { org.house_roles.create!(name: "Bar back") }
  let(:door) { org.house_roles.create!(name: "Door") }
  let(:miles) { create(:person, name: "Miles") }
  let(:camille) { create(:person, name: "Camille") }
  let(:jo) { create(:person, name: "Jo Back") }
  let(:pat) { create(:person, name: "Pat Door") }

  def at(hour) = hour >= 24 ? (night + 1.day).change(hour: hour - 24) : night.change(hour: hour)

  def shift(person, role, from, to)
    org.shifts.create!(house_role: role, starts_at: at(from), ends_at: at(to)).shift_assignments.create!(person: person)
  end

  before do
    [ miles, camille, jo, pat ].each { |p| org.organization_staff_members.create!(person: p) }
    shift(miles, bartender, 18, 22)
    shift(camille, bartender, 20, 24)
    shift(pat, door, 18, 24)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "has a Tips section in Money settings where the roles are set, off by default" do
    get manage_money_settings_section_path(section: "tips")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Work out the split from who was working", "Bartender", "Bar back", "Door", "A fixed cut off the top")

    patch manage_money_settings_tips_path, params: { enabled: "1", roles: { bartender.id => { share: "equal" }, bar_back.id => { share: "percent", percent: "15" }, door.id => { share: "out" } } }
    rule = org.reload.tip_rule
    expect(rule).to be_enabled
    expect(rule.role_shares).to eq({ bartender.id.to_s => { "kind" => "equal" }, bar_back.id.to_s => { "kind" => "percent", "percent" => 15.0 } })
    expect(flash[:notice]).to include("Tips settings saved")
  end

  it "stays the by-hand split while the rule is off" do
    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("By hours worked", "Pat Door")
    expect(response.body).not_to include("Tips go to the people on the bar")
  end

  context "with the rule on" do
    before { org.create_tip_rule!(enabled: true, role_shares: { bartender.id.to_s => { "kind" => "equal" }, bar_back.id.to_s => { "kind" => "percent", "percent" => 15 } }) }

    it "ignores an even split saved before the rule, lists only the sharing roles, and drops the stray shares on save" do
      # The by-hand page confirmed an even three-way split while the rule
      # was off: $80 each for Miles, Pat on the door and Camille, no roles.
      record = SettlementDay.create!(organization: org, date: date, tips_split: "even")
      [ miles, pat, camille ].each { |p| record.tip_shares.create!(person: p, amount_cents: 8_000, method: "payout", source: "typed") }

      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).not_to include(%(name="shares[#{pat.id}]), "Typed in")
      expect(response.body).to include(%(name="shares[#{miles.id}][amount]" inputmode="decimal" value="120.00"))

      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1" }
      expect(record.tip_shares.reload.map { |sh| [ sh.person.name, sh.amount_cents, sh.source ] }).to contain_exactly([ "Miles", 12_000, "computed" ], [ "Camille", 12_000, "computed" ])
    end

    it "opens already split by the clock, with each span and how, and leaves the door out" do
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Worked out from who was on when each sale rang up: Bartender keeps what rang up while on; Bar back 15% off the top")
      expect(response.body).to include("Miles", "Camille", "From 32 orders while on.", "Change the split", "Add a person who worked", "Change the rule", "6 pm to 10 pm")
      expect(response.body).not_to include(%(name="shares[#{pat.id}][amount]"))
      expect(response.body).to include(%(name="shares[#{miles.id}][amount]" inputmode="decimal" value="120.00"))
      expect(response.body).to include(%(name="shares[#{miles.id}][from]" value="18:00"), %(name="shares[#{miles.id}][to]" value="22:00"))
    end

    it "saves the split, adds a bar back with a span, keeps a typed share, and sends the shares to the run on settle" do
      # Saved as worked out: $120 each.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "0",
        shares: { miles.id => { amount: "120.00", shown: "120.00", method: "payout", from: "18:00", to: "22:00", span_shown: "18:00-22:00", house_role_id: bartender.id },
                  camille.id => { amount: "120.00", shown: "120.00", method: "payout", from: "20:00", to: "00:00", span_shown: "20:00-00:00", house_role_id: bartender.id } } }
      record = SettlementDay.find_by!(organization: org, date: date)
      expect(record.tip_shares.pluck(:source).uniq).to eq([ "computed" ])
      expect(record.tip_shares.sum(:amount_cents)).to eq(24_000)
      expect(record.tip_shares.find_by(person: miles).worked_from).to be_nil # Staffing's span, not set by hand

      # Jo worked the bar back from 8 to 10: 15% of those two hours ($80) is $12, off the top.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "0", new_share: { person_id: jo.id, house_role_id: bar_back.id, from: "20:00", to: "22:00" } }
      jo_share = record.tip_shares.find_by!(person: jo)
      expect(jo_share.amount_cents).to eq(1_200)
      expect(jo_share.worked_from).to eq(night.change(hour: 20))
      expect(jo_share.worked_to).to eq(night.change(hour: 22))
      expect(record.tip_shares.sum(:amount_cents)).to eq(24_000)
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("Jo Back", "15% off the top while on.")

      # Camille's share typed to $100: it stays, and the rest adjust around it.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1",
        shares: { camille.id => { amount: "100.00", shown: record.tip_shares.find_by(person: camille).amount_cents.then { |c| format("%.2f", c / 100.0) }, method: "payout" } } }
      expect(record.tip_shares.find_by(person: camille)).to have_attributes(amount_cents: 10_000, source: "typed")
      expect(record.tip_shares.sum(:amount_cents)).to eq(24_000)
      expect(record.reload.tips_checked_at).to be_present
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("Typed in.", "Work it all out again")

      # Back in the clock's hands.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1", recompute: "1", shares: { camille.id => { amount: "100.00", shown: "100.00", method: "payout" } } }
      expect(record.tip_shares.find_by(person: camille).source).to eq("computed")

      # A span changed by hand sticks, and the shares follow it: Miles off at 8 leaves the 8–10 stretch to Camille.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1",
        shares: { miles.id => { amount: "0", shown: "0", method: "payout", from: "18:00", to: "20:00", span_shown: "18:00-22:00", house_role_id: bartender.id } } }
      expect(record.tip_shares.find_by(person: miles)).to have_attributes(worked_to: night.change(hour: 20), amount_cents: 8_000, source: "computed")

      patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
      post manage_settle_money_settle_up_day_path(date.iso8601)
      expect(record.reload).to be_settled
      expect(ChartOfAccounts.account(org, :tips_owed).natural_balance_cents).to eq(24_000)
      # Settling puts nothing on the run: the shares wait on Pay People.
      expect(PayoutContribution.where(payee: [ miles, camille, jo ]).count).to eq(0)
      expect(TipShare.waiting_for(org).sum(:amount_cents)).to eq(24_000)

      # Pay People offers them like approved hours, and ties each share to the
      # run's Tips line when the week's pay goes on.
      get manage_staffing_pay_path
      expect(response.body).to include("3 people", "tips waiting from Settle up — $240.00 to pay through us", "Pull in tips")
      miles_share = record.tip_shares.find_by!(person: miles)
      member = org.organization_staff_members.find_by!(person: miles)
      expect(response.body).to include(%(data-tips-waiting="#{ERB::Util.html_escape([ { id: miles_share.id, date: date.strftime("%b %-d"), amount: format("%.2f", miles_share.amount_cents / 100.0), method: "payout" } ].to_json)}"))

      post manage_create_staffing_pay_path, params: { payday: Date.current.iso8601, lines: { member.id => { tips: format("%.2f", miles_share.amount_cents / 100.0), tips_sheet: [ "#{date.strftime("%b %-d")}|#{format("%.2f", miles_share.amount_cents / 100.0)}" ], tip_share_ids: [ miles_share.id ] } } }
      expect(response).to have_http_status(:redirect)
      expect(miles_share.reload.payout_contribution).to have_attributes(label: "Tips", amount_cents: miles_share.amount_cents)
      expect(miles_share.payout_contribution.payout_batch).to be_open
      expect(TipShare.waiting_for(org).map(&:person)).to contain_exactly(camille, jo)

      # Reopening the day takes Miles's share back off the draft run.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Wrong split" }
      expect(miles_share.reload.payout_contribution).to be_nil
    end
  end
end

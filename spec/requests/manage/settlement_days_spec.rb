# frozen_string_literal: true

require "rails_helper"

# Settle up (Books V1.3): one worksheet per day that had money in it.
RSpec.describe "Settle up", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  # A production that pays nobody: these are the money-side specs; who gets paid is below.
  let(:production) { create(:production, organization: org, name: "Halloween Show", pays_performers: false) }
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
    expect(response.body).to include(date.strftime("%A, %B %-d"), "Confirm", "0 of 1 confirmed", "Settle the day")

    # Not every piece is checked: settling is refused.
    post manage_settle_money_settle_up_day_path(date.iso8601)
    expect(SettlementDay.find_by(organization: org, date: date)).to be_nil
    expect(flash[:alert]).to include("Confirm every piece")

    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    expect(show.reload.show_financials.data_confirmed).to be(true)

    post manage_settle_money_settle_up_day_path(date.iso8601)
    record = SettlementDay.find_by!(organization: org, date: date)
    expect(record).to be_settled
    expect(record.settled_by).to eq(owner)

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include(%(id="day-settled"), "Settled", "Reopen this day")
    expect(response.body).not_to include("Confirm each piece")

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

  it "types the ticket money for a show CocoScout doesn't sell: tickets, a flat fee or no revenue, and a note, with no link to the old page" do
    back = manage_money_settle_up_day_path(date.iso8601)
    get back
    expect(response.body).to include(%(data-modal-id="tickets-#{show.id}"), %(data-modal-id="notes-#{show.id}"), "nothing entered yet", "This show had no revenue")
    expect(CGI.unescapeHTML(response.body)).not_to include("This show's page")

    patch manage_update_money_show_financials_path(show), params: { return_to: back, revenue_choice: "ticket_sales",
      show_financials: { flat_fee: "", ticket_sales_lines_attributes: { "0" => { ticket_source_id: "", tickets_sold: "30", amount: "450" } } } }
    expect(response).to redirect_to(back)
    fin = show.reload.show_financials
    expect([ fin.ticket_count, fin.ticket_revenue.to_f, fin.data_confirmed ]).to eq([ 30, 450.0, false ])
    get back
    # A ticket with no type of its own reads as the plain one.
    expect(response.body).to include("30 General Admission</span>", "", "Outside tickets", "Ticket type")

    # Another type for the same show: every line names its type, on the card and in the modal.
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    patch manage_update_money_show_financials_path(show), params: { return_to: back, revenue_choice: "ticket_sales",
      show_financials: { ticket_sales_lines_attributes: { "0" => { ticket_source_id: tailor.id, ticket_type: " VIP ", tickets_sold: "2", amount: "80" },
                                                           "1" => { ticket_source_id: tailor.id, ticket_type: "General Admission", tickets_sold: "5", amount: "100" } } } }
    expect(fin.reload.ticket_sales_lines.where(ticket_source: tailor).pluck(:ticket_type, :tickets_sold)).to contain_exactly([ "VIP", 2 ], [ "General Admission", 5 ])
    get back
    expect(response.body).to include("2 VIP,</span>", "5 General Admission</span>", "$180.00")
    expect(response.body.scan(/name="show_financials\[ticket_sales_lines_attributes\]\[\d+\]\[ticket_type\]"[^>]*value="VIP"/).size).to eq(1)
    fin.ticket_sales_lines.where(ticket_source: tailor).each(&:destroy!)

    patch manage_update_money_show_financials_path(show), params: { return_to: back, revenue_choice: "flat_fee", show_financials: { flat_fee: "500" } }
    expect(fin.reload).to be_flat_fee
    get back
    expect(response.body).to include("A flat fee instead of tickets", "$500.00")

    # A note changes no money, so the mark stays lit.
    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    patch manage_update_money_show_financials_path(show), params: { return_to: back, show_financials: { notes: "Rained out early" } }
    expect([ fin.reload.notes, fin.data_confirmed ]).to eq([ "Rained out early", true ])
    get back
    expect(response.body).to include("Rained out early")

    # No revenue: nothing counted, nobody paid, still confirmed with the day, and chosen back the same way.
    patch manage_update_money_show_financials_path(show), params: { return_to: back, revenue_choice: "none", show_financials: { flat_fee: "500" } }
    expect([ fin.reload.non_revenue_override, fin.data_confirmed ]).to eq([ true, false ])
    expect(SettleUp.day(org, date).shows.first.in_cents).to eq(0)
    get back
    expect(response.body).to include("this show had no revenue", "No revenue, not confirmed", "Nobody is paid from a show with no revenue")
    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    expect(fin.reload.data_confirmed).to be(true)
    patch manage_update_money_show_financials_path(show), params: { return_to: back, revenue_choice: "flat_fee", show_financials: { flat_fee: "500" } }
    expect([ fin.reload.non_revenue_override, fin.flat_fee.to_f ]).to eq([ false, 500.0 ])
  end

  it "opens the same outside tickets modal on a settled day, to read and not to change" do
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    org.ticket_sources.create!(name: "Hot Tix")
    fin = show.show_financials || show.create_show_financials!
    fin.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 9, amount: 150)
    back = manage_money_settle_up_day_path(date.iso8601)

    get back
    expect(response.body).to include("9 General Admission</span>", "", %(data-modal-id="tickets-#{show.id}"), "show_financials[ticket_sales_lines_attributes]", "Hot Tix")

    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    post manage_settle_money_settle_up_day_path(date.iso8601)
    expect(SettlementDay.find_by!(organization: org, date: date)).to be_settled

    get back
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("9 General Admission</span>", "", %(data-modal-id="tickets-#{show.id}"), "The day is settled. Reopen it to change these.")
    # Only what sold is listed, as plain numbers.
    expect(body).not_to include("show_financials[ticket_sales_lines_attributes]", "Edit ticket sources")
  end

  it "uses that modal for a show sold through CocoScout too, a line per site and ticket type of its own" do
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    listing = TicketListing.create!(show: show)
    general = listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000, quantity: 10)
    back = manage_money_settle_up_day_path(date.iso8601)

    get back
    expect(response.body).to include("Sold on other sites", "Outside tickets", %(action="#{manage_ticket_listing_outside_sales_path(listing)}"),
                                     %(name="sales[#{tailor.id}][#{general.id}][tickets]"), %(name="sales[#{tailor.id}][#{vip.id}][amount]"))
    expect(response.body).not_to include("revenue_choice", "Sold elsewhere")

    patch manage_ticket_listing_outside_sales_path(listing), params: { return_to: back,
      sales: { tailor.id.to_s => { general.id.to_s => { tickets: "4", amount: "80" }, vip.id.to_s => { tickets: "1", amount: "40" } } } }
    expect(response).to redirect_to(back)
    get back
    expect(response.body).to include("4 General,</span>", "1 VIP</span>", "$120.00")

    # What sold through CocoScout names its ticket types the same way.
    order = TicketOrder.create!(organization: org, ticket_listing: listing, buyer_email: "pat@example.com", buyer_name: "Pat", status: "paid", channel: "online", money_path: "cocoscout", fee_mode: "buyer")
    2.times { order.tickets.create!(ticket_listing: listing, ticket_tier: general, price_cents: 2_000, status: "valid") }
    order.tickets.create!(ticket_listing: listing, ticket_tier: vip, price_cents: 4_000, status: "valid")
    TicketSalesSync.sync!(show)
    get back
    expect(response.body).to include("Sold through CocoScout", "2 General,</span>", "1 VIP</span>", "$80.00")
    expect(response.body).not_to include("from Ticketing</span><span class='tabular-nums text-gray-900'><a")
  end

  it "says a show sold here once before anything sells, and gives other sites one line for a ticket that has a door price too" do
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    listing = TicketListing.create!(show: show)
    online = listing.ticket_tiers.create!(name: "Reserve a spot", price_cents: 1_500, quantity: 30, sells_at: "online")
    door = listing.ticket_tiers.create!(name: "Reserve a spot", price_cents: 2_000, quantity: 30, sells_at: "door", position: 1)
    back = manage_money_settle_up_day_path(date.iso8601)

    get back
    expect(response.body).to include("Sold through CocoScout", "0 tickets</span>", "Sold on other sites", %(name="sales[#{tailor.id}][#{online.id}][tickets]"))
    expect(response.body).not_to include("nothing entered yet", "Checked in", %(name="sales[#{tailor.id}][#{door.id}][tickets]"), %(name="sales[new][#{door.id}][tickets]"))

    # Numbers already saved against the door's type stay in sight, each line saying its price.
    TicketOutsideSales.record!(listing, { tailor.id.to_s => { door.id.to_s => { "tickets" => "2", "amount" => "40" } } })
    get back
    expect(response.body).to include(%(name="sales[#{tailor.id}][#{door.id}][tickets]"), "$15.00, online only", "$20.00, at the door only")
  end

  it "keeps a show's financials page as a read-only record of its day's card and what was left" do
    fin = show.show_financials || show.create_show_financials!
    fin.update!(ticket_count: 30, ticket_revenue: 450, data_confirmed: true)
    fin.expense_items.create!(category: ExpenseItem::CATEGORIES.first, description: "Pizza", amount: 50)

    org.update!(settle_up_starts_on: date)
    get manage_money_show_financials_path(show)
    expect(response).to have_http_status(:ok)
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Settles with #{date.strftime('%A, %B %-d')}", "Settle up, #{date.strftime('%b %-d')}", "30 tickets</span>", "", "What was left", "Came in", "$400.00")
    # The ticket numbers open the same modal as on the day, to read: nothing to type or save.
    expect(body).to include(%(data-modal-id="tickets-#{show.id}"), "Outside tickets")
    expect(body).not_to include("Enter Financial Data", "Mark as Non-Revenue", "show_financials[ticket_sales_lines_attributes]", "Confirm</span>")
    # A needs-financials row and the payout page send people to the day, the card open.
    expect(SettleUp.money_entry_path(org, show)).to eq(manage_money_settle_up_day_path(date.iso8601, open: show.id, anchor: "show-#{show.id}"))

    # From before the start date: the record says how to bring it in.
    org.update!(settle_up_starts_on: date + 30)
    get manage_money_show_financials_path(show)
    expect(CGI.unescapeHTML(response.body)).to include("From before Settle up started", "Change the start date")
    expect(SettleUp.money_entry_path(org, show)).to eq(manage_money_show_financials_path(show))
  end

  it "brings days already confirmed in settled when the start date moves earlier, and leaves unfinished ones to settle" do
    other = create(:show, production: production, date_and_time: 5.days.ago.change(hour: 20))
    (show.show_financials || show.create_show_financials!).update!(ticket_count: 10, ticket_revenue: 100, data_confirmed: true)
    (other.show_financials || other.create_show_financials!).update!(ticket_count: 5, ticket_revenue: 50, data_confirmed: false)
    org.update!(settle_up_starts_on: Date.current)

    patch manage_money_settings_settle_up_path, params: { settlement_day_mode: "smart", settlement_day_starts_at: "5", settle_up_starts_on: 10.days.ago.to_date.iso8601 }
    expect(flash[:notice]).to include("1 day already confirmed came in settled; 1 is waiting to settle")
    expect(SettlementDay.find_by(organization: org, date: date)).to be_settled
    expect(SettlementDay.find_by(organization: org, date: SettlementDay.day_for(org, other.date_and_time))).to be_nil
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
    expect(response.body).to include(manage_money_settle_up_day_path(date.iso8601), "Bar, Lincoln Lodge")

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("Bar, Lincoln Lodge", "$100.00", "$20.00", "Sales tax collected", "Tips, $15.00", "Pat Bartender", "To your bank from Square", "Pulled in automatically from Square, which sends the money straight to your bank, not through CocoScout.", "Manage Square integration")

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
      expect(response.body).to include("Miles", "Camille", "From 32 orders while on.", "Change the split", "Add someone", "Take off", "Change the rule", "6 pm to 10 pm")
      # One small way into the math, and the math itself: the shared stretch, what rang up in it, and each one's half.
      expect(response.body.scan("View share calculation").size).to eq(1)
      expect(response.body).to include("Share calculation", "By who was on", "Adds up to")
      expect(response.body).not_to include(%(name="shares[#{pat.id}][amount]"))
      expect(response.body).to include(%(name="shares[#{miles.id}][amount]" inputmode="decimal" value="120.00"))
      expect(response.body).to include(%(name="shares[#{miles.id}][from]" value="18:00"), %(name="shares[#{miles.id}][to]" value="22:00"))
    end

    it "asks who gets a stretch with nobody on the bar, by stretch, and won't check the register until it's answered" do
      # Miles on from 7, not 6: nobody on the bar 6 to 7, $40 from 8 orders.
      org.shifts.find_by!(starts_at: at(18)).update!(starts_at: at(19))
      key = SquareSync.quarter_key(night.change(hour: 18))

      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("Nobody on the bar 6 pm to 7 pm: $40.00 from 8 orders. Say who gets it under Change the split.")
      expect(response.body).to include(%(name="unstaffed[#{key}]"), "The house keeps it", "Split between everyone listed")
      expect(response.body).not_to include("from the pool")
      # The tips are in the Square card, with one Looks right for both.
      expect(response.body).not_to include("Tips, $240.00 Not checked yet")
      expect(response.body).to include("Tips <span class=\"text-xs text-gray-500\">who gets them, below</span>")

      patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
      expect(flash[:alert]).to include("Say who gets the tips rung up with nobody on the bar first")
      expect(SettlementDay.find_by(organization: org, date: date)&.register_checked_at).to be_nil

      # The house keeps it: the rows add up to $200, and settling books $40 as the house's.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", unstaffed: { key => "house" } }
      record = SettlementDay.find_by!(organization: org, date: date)
      expect(record.tips_unstaffed).to eq({ key => "house" })
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("Nobody on the bar 6 pm to 7 pm: $40.00 from 8 orders, the house keeps it.")
      expect(response.body).not_to include("The house keeps $40.00.")
      expect(record.tip_shares.sum(:amount_cents)).to eq(20_000)

      # Or Miles gets it, whole.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", unstaffed: { key => miles.id.to_s } }
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("to Miles.", "plus $40.00 from when nobody was on.")
      # Miles's $80 while on plus the $40: $120, level with Camille's $120.
      expect(record.tip_shares.find_by(person: miles).amount_cents).to eq(12_000)

      # Back to the house, checked and settled: $200 owed, $40 the house's income.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", unstaffed: { key => "house" } }
      patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
      expect(record.reload.register_checked_at).to be_present
      post manage_settle_money_settle_up_day_path(date.iso8601)
      expect(record.reload).to be_settled
      expect(ChartOfAccounts.account(org, :tips_owed).natural_balance_cents).to eq(20_000)
      expect(ChartOfAccounts.account(org, :other_income).natural_balance_cents).to eq(4_000)
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
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("Typed in.", "Work it all out again")

      # Back in the clock's hands.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1", recompute: "1", shares: { camille.id => { amount: "100.00", shown: "100.00", method: "payout" } } }
      expect(record.tip_shares.find_by(person: camille).source).to eq("computed")

      # A span changed by hand sticks, and the shares follow it: Miles off at 8 leaves the 8–10 stretch to Camille.
      patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1",
        shares: { miles.id => { amount: "0", shown: "0", method: "payout", from: "18:00", to: "20:00", span_shown: "18:00-22:00", house_role_id: bartender.id } } }
      expect(record.tip_shares.find_by(person: miles)).to have_attributes(worked_to: night.change(hour: 20), amount_cents: 8_000, source: "computed")

      # The register's Looks right covers the tips (they are in the Square card).
      patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
      expect(record.reload.tips_checked_at).to be_present
      post manage_settle_money_settle_up_day_path(date.iso8601)
      expect(record.reload).to be_settled
      expect(ChartOfAccounts.account(org, :tips_owed).natural_balance_cents).to eq(24_000)
      # Settling puts nothing on the run: the shares wait on Pay People.
      expect(PayoutContribution.where(payee: [ miles, camille, jo ]).count).to eq(0)
      expect(TipShare.waiting_for(org).sum(:amount_cents)).to eq(24_000)
      # The settled day says so, in one pill on the tips, and the reopen modal says they'd stop waiting.
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body.scan("Waiting on Pay People").size).to eq(1)
      expect(CGI.unescapeHTML(response.body)).to include("Its tips, $240.00 for 3 people, stop waiting on Pay People until the day settles again.")

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

      # Now the pill counts where each share stands, and each row tags its own.
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("2 waiting on Pay People · 1 on the draft payout run", "· on a payout run")

      # Another settled day's share for Miles rides the same Tips line (a week's tips are one line).
      earlier = SettlementDay.create!(organization: org, date: date - 1, status: "settled", settled_at: Time.current)
      line = miles_share.payout_contribution
      other_share = earlier.tip_shares.create!(person: miles, amount_cents: 1_500, method: "payout", source: "computed", payout_contribution: line)
      line.update!(amount_cents: line.amount_cents + 1_500, worksheet: line.worksheet_entries + [ { "date" => other_share.day_label, "amount_cents" => 1_500 } ])
      line.payout_ledger_entries.update_all(amount_cents: line.amount_cents)
      line.payout_batch_item.settle_amount!

      # Reopening the day takes Miles's share back off the draft run, and says so.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Wrong split" }
      expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601))
      expect(flash[:notice]).to include("Miles's tips came off the draft payout run")
      expect(miles_share.reload.payout_contribution).to be_nil
      # Only this day's share came off: the other day's stays on the line, which is now just its amount.
      expect(other_share.reload.payout_contribution).to eq(line)
      expect(line.reload).to have_attributes(amount_cents: 1_500, worksheet: [ { "date" => other_share.day_label, "amount_cents" => 1_500 } ])
      expect(line.payout_ledger_entries.pluck(:amount_cents)).to eq([ 1_500 ])
      expect(line.payout_batch_item.reload.amount_cents).to eq(1_500)
      expect(TipShare.waiting_for(org)).not_to include(miles_share)
      expect(record.reload).not_to be_settled

      # With nothing else on the line, the line and the person's place on the run go with it, and the page still comes back.
      earlier.update!(status: "settled")
      post manage_reopen_money_settle_up_day_path((date - 1).iso8601), params: { reason: "And this one" }
      expect(response).to redirect_to(manage_money_settle_up_day_path((date - 1).iso8601))
      expect(other_share.reload.payout_contribution).to be_nil
      expect(PayoutContribution.exists?(line.id)).to be(false)
    end

    # Paid means the run was submitted (Tim, 2026-11-04). A day reopened
    # after that keeps what was paid and lets the split change: more owed
    # waits on Pay People, overpaid comes out of the person's next pay.
    it "keeps tips a submitted run paid when the day is reopened, and carries the difference through Pay People" do
      day_label = date.strftime("%b %-d")
      split = ->(miles_to) do
        patch manage_tips_money_settle_up_day_path(date.iso8601), params: { mode: "rule", checked: "1",
          shares: { miles.id => { amount: "0", shown: "0", method: "payout", from: "18:00", to: miles_to, span_shown: "x", house_role_id: bartender.id },
                    camille.id => { amount: "0", shown: "0", method: "payout", from: "20:00", to: "00:00", span_shown: "x", house_role_id: bartender.id } } }
      end
      settle = -> do
        patch manage_check_register_money_settle_up_day_path(date.iso8601), params: { checked: "1" }
        post manage_settle_money_settle_up_day_path(date.iso8601)
      end
      pay_out = ->(run) do
        run.update!(status: "completed")
        run.items.each { |item| item.mark_paid!(transfer_id: "tr_#{item.id}") }
      end
      member = ->(person) { org.organization_staff_members.find_by!(person: person) }

      split.call("22:00")
      settle.call
      record = SettlementDay.find_by!(organization: org, date: date)
      miles_share = record.tip_shares.find_by!(person: miles)
      camille_share = record.tip_shares.find_by!(person: camille)
      expect([ miles_share.amount_cents, camille_share.amount_cents ]).to eq([ 12_000, 12_000 ])

      # The week's pay goes on a run with both shares, and the run is submitted and paid.
      post manage_create_staffing_pay_path, params: { payday: Date.current.iso8601, lines: {
        member.call(miles).id => { tips: "120.00", tips_sheet: [ "#{day_label}|120.00" ], tip_share_ids: [ miles_share.id ] },
        member.call(camille).id => { tips: "120.00", tips_sheet: [ "#{day_label}|120.00" ], tip_share_ids: [ camille_share.id ] } } }
      first_run = PayoutBatch.current_open_draft(org)
      pay_out.call(first_run)

      get manage_money_settle_up_day_path(date.iso8601)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Already paid, and staying paid", "Miles, $120.00 in tips", "Camille, $120.00 in tips", "tips wait on Pay People")
      expect(body).not_to include("stop waiting on Pay People until the day settles again")

      # Reopening leaves the money paid and frees the split.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Miles left at 8" }
      expect(flash[:notice]).not_to include("came off the draft payout run")
      expect(miles_share.reload).to have_attributes(paid_cents: 12_000, payout_contribution_id: nil, amount_cents: 12_000)
      expect(first_run.reload.payout_contributions.sum(:amount_cents)).to eq(24_000)

      # Miles off at 8: $80 for him, $160 for Camille.
      split.call("20:00")
      expect([ miles_share.reload.amount_cents, camille_share.reload.amount_cents ]).to eq([ 8_000, 16_000 ])
      get manage_money_settle_up_day_path(date.iso8601)
      expect(CGI.unescapeHTML(response.body)).to include("Paid $120.00. The $40.00 over comes out of their next pay.", "Paid $120.00. $40.00 more waits on Pay People.")

      settle.call
      expect(TipShare.waiting_for(org)).to contain_exactly(camille_share)
      expect(TipShare.overpaid_for(org)).to contain_exactly(miles_share)
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("1 overpaid, comes out of their next pay · 1 waiting on Pay People")

      # Pay People offers Camille only the difference, and says what comes out of Miles's pay.
      get manage_staffing_pay_path
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("tips waiting from Settle up — $40.00 to pay through us", "$40.00 in tips paid over on #{day_label} comes out of their next pay that covers it.",
        %(data-comes-out-cents="4000"), { id: camille_share.id, date: day_label, amount: "40.00", method: "payout" }.to_json)

      # A pay too small to cover it is left whole.
      post manage_create_staffing_pay_path, params: { payday: Date.current.iso8601, lines: { member.call(miles).id => { bonus: "30.00" } } }
      run = PayoutBatch.current_open_draft(org)
      expect(run.items.find_by(payee: miles).amount_cents).to eq(3_000)
      expect(miles_share.reload.payout_contribution).to be_nil

      # The next one that covers it pays that much less, on a line of its own; Camille's difference rides her Tips line.
      post manage_create_staffing_pay_path, params: { payday: Date.current.iso8601, lines: {
        member.call(miles).id => { bonus: "100.00" },
        member.call(camille).id => { tips: "40.00", tips_sheet: [ "#{day_label}|40.00" ], tip_share_ids: [ camille_share.id ] } } }
      expect(run.items.find_by(payee: miles).reload.amount_cents).to eq(3_000 + 10_000 - 4_000)
      expect(miles_share.reload.payout_contribution).to have_attributes(label: "Tips paid over", amount_cents: -4_000, category: "staffing",
                                                                        worksheet: [ { "date" => day_label, "amount_cents" => -4_000 } ])
      expect(camille_share.reload.payout_contribution).to have_attributes(label: "Tips", amount_cents: 4_000)
      expect(TipShare.overpaid_for(org)).to be_empty
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("On the draft payout run")

      # Paid out, everyone's staff balance is square.
      pay_out.call(run)
      expect([ miles, camille ].map { |person| org.payout_balance_cents_for(person, category: "staffing") }).to eq([ 0, 0 ])

      # Reopened once more with nothing changed: nothing is owed either way.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Just looking" }
      expect([ miles_share.reload.paid_cents, camille_share.reload.paid_cents ]).to eq([ 8_000, 16_000 ])
      settle.call
      expect(TipShare.waiting_for(org)).to be_empty
      expect(TipShare.overpaid_for(org)).to be_empty
    end
  end
end

# Paying people from the day (Tim, 2026-11-04): who gets paid is on each
# show's card once its money is confirmed, each line has a choice, settling
# the day puts the "on the run" lines on the open payout run, and reopening
# takes them back off a draft.
RSpec.describe "Manage::SettlementDays pays people", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "calendar", settle_up_starts_on: Date.current - 30) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Pavlov") }
  let!(:show) { create(:show, production: production, date_and_time: 2.days.ago.change(hour: 20)) }
  let(:date) { SettlementDay.day_for(org, show.date_and_time) }
  let(:ana) { create(:person, name: "Ana Diaz") }
  let(:ben) { create(:person, name: "Ben Lee") }
  let(:even_split) { create(:payout_scheme, organization: org, production: nil, name: "Even split", rules: { "allocation" => [], "distribution" => { "method" => "equal" } }) }

  before do
    create(:show_financials, show: show, ticket_count: 20, ticket_revenue: 200.0, expenses: 0)
    [ ana, ben ].each { |person| create(:show_person_role_assignment, show: show, assignable: person) }
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "asks how the production pays before the show can be confirmed, and remembers the answer for every show" do
    get manage_money_settle_up_day_path(date.iso8601)
    expect(CGI.unescapeHTML(response.body)).to include("Pavlov has no payout calculation yet", "Say how it's paid", "Say how Pavlov pays its performers first")

    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    expect(flash[:alert]).to include("Say how Pavlov pays its performers first")
    expect(show.reload.show_financials.data_confirmed).to be(false)

    patch manage_choose_calculation_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { choice: "existing", payout_scheme_id: even_split.id, scope: "production" }
    expect(flash[:notice]).to include("Every Pavlov show uses Even split")
    expect(PayoutScheme.current_default_for_production(production.reload, on: date)).to eq(even_split)
    expect(production.payout_calculation_mode).to eq("production")

    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("Who gets paid", "not worked out yet", "Even split", "Ana Diaz", "Ben Lee", "From the numbers as they stand, $200.00 to 2 people", "Calculate")
    expect(response.body.scan("Worked out when the money is confirmed")).to be_empty
  end

  it "can be asked for each show instead, or told nobody is paid" do
    patch manage_choose_calculation_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { choice: "existing", payout_scheme_id: even_split.id, scope: "show" }
    expect(production.reload.payout_calculation_mode).to eq("each_show")
    expect(show.reload.show_payout.payout_scheme).to eq(even_split)
    expect(PayoutScheme.current_default_for_production(production, on: date)).to be_nil

    other = create(:show, production: production, date_and_time: 1.day.ago.change(hour: 20))
    create(:show_financials, show: other, ticket_count: 10, ticket_revenue: 100.0, expenses: 0)
    get manage_money_settle_up_day_path(SettlementDay.day_for(org, other.date_and_time).iso8601)
    expect(CGI.unescapeHTML(response.body)).to include("Pavlov asks which calculation each show uses", "Choose this show's calculation first")

    patch manage_choose_calculation_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { choice: "nobody" }
    expect(production.reload.pays_performers).to be(false)
    expect(flash[:notice]).to include("its shows settle without a payout")
    get manage_money_settle_up_day_path(date.iso8601)
    expect(response.body).to include("No performers are paid for Pavlov", "Set up a payout")
    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    expect(flash[:notice]).to include("confirmed")
  end

  context "with the production's calculation chosen" do
    before { even_split.make_production_scheme!(production) }

    it "is calculated first, then confirmed, keeps each line's choice, puts the run lines on the run when the day settles, and takes them back on reopen" do
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      expect(flash[:alert]).to include("Calculate the payout first")
      expect(show.reload.show_payout).to be_nil

      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601, open: show.id))
      expect(flash[:notice]).to eq("Pavlov Show: $200.00 to 2 people.")
      payout = show.reload.show_payout
      expect(payout.calculated_at).to be_present
      expect(payout.line_items.map { |l| [ l.payee_name, l.amount.to_f, l.pay_choice ] }).to contain_exactly([ "Ana Diaz", 100.0, "run" ], [ "Ben Lee", 100.0, "run" ])

      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      expect(response.body).to include("$200.00 to 2 people", "Hold, not yet", "Paid another way…", "Remove from this show", "Who's paid and how", "$200.00 for 2 people goes on the payout run")
      expect(response.body).not_to include("<select name=\"pay_choice\"")
      expect(response.body).not_to include("Recalculate")

      # The numbers move under it: the card says so, and the show waits on a recalculation.
      travel 2.seconds
      show.show_financials.update!(ticket_revenue: 300.0)
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("The numbers changed since this was worked out", "$300.00 to 2 people", "Recalculate")
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      expect(flash[:alert]).to include("The numbers changed; recalculate first")
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      expect(payout.reload.line_items.sum(&:amount).to_f).to eq(300.0)
      payout.line_items.each { |l| l.update!(amount: 100.0) }
      payout.update!(total_payout: 200.0)

      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      expect(flash[:notice]).to include("confirmed")
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("1 of 1 confirmed").or include("Every piece is confirmed")
      expect(response.body).not_to include("Recalculate")

      ben_line = payout.line_items.find_by(payee: ben)
      patch manage_pay_line_money_settle_up_day_path(date.iso8601, show_id: show.id, line_id: ben_line.id), params: { pay_choice: "hold" }
      expect(ben_line.reload).to be_held
      expect(flash[:notice]).to include("Ben Lee: held for now")

      post manage_settle_money_settle_up_day_path(date.iso8601)
      expect(flash[:notice]).to include("$100.00 for 1 person went on the draft payout run")
      run = PayoutBatch.current_open_draft(org)
      expect(run).to be_present
      expect(PayoutContribution.find_by(source: payout.line_items.find_by(payee: ana))&.payout_batch).to eq(run)
      expect(PayoutContribution.find_by(source: ben_line)).to be_nil

      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include(%(id="day-settled"), "1 payout from this day is on the draft payout run.", "1 on the draft payout run", "1 held", "The payout run")

      # The reopen modal says what it undoes and asks about the payouts on the draft run.
      expect(CGI.unescapeHTML(response.body)).to include("Reopening undoes what settling did", "1 payout from this day, $100.00, is on the draft payout run.",
        "Take it off the run, so the pay can change.", "Leave it on the run. I'm changing something else")

      # Kept on the run: the day opens, the line stays and its show stays locked.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Door cash was off", payouts: "keep" }
      expect(flash[:notice]).to include("Its payouts stayed on the draft payout run")
      expect(PayoutContribution.find_by(source: payout.line_items.find_by(payee: ana))&.payout_batch).to eq(run)
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      post manage_settle_money_settle_up_day_path(date.iso8601)
      expect(PayoutContribution.where(source_type: "ShowPayoutLineItem", source_id: payout.line_items.ids).count).to eq(1)

      # Taken off (the default): the line comes back off the draft and rides again on settling.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "A ticket count was wrong" }
      expect(flash[:notice]).to include("$100.00 for 1 person came off the draft payout run")
      expect(PayoutContribution.where(source_type: "ShowPayoutLineItem", source_id: payout.line_items.ids)).not_to exist
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("1 held", "$100.00 for 1 person goes on the payout run when the day settles")
    end

    # Paid means the run was submitted (Tim, 2026-11-04): from then on the
    # money stays paid, and a day reopened after it carries the difference.
    def submit_and_pay!(run)
      run.update!(status: "completed")
      run.items.each do |item|
        item.mark_paid!(transfer_id: "tr_#{item.id}")
        PayoutBatchService.settle_item_sources!(item, "tr_#{item.id}")
      end
    end

    def settle_day!
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      post manage_settle_money_settle_up_day_path(date.iso8601)
    end

    it "keeps what a submitted run paid when the day is reopened, and puts more owed on the next draft run" do
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      settle_day!
      first_run = PayoutBatch.current_open_draft(org)
      submit_and_pay!(first_run)
      payout = show.reload.show_payout
      expect(payout.line_items.map(&:paid?)).to eq([ true, true ])

      # Reopening takes nothing back: the run was submitted.
      get manage_money_settle_up_day_path(date.iso8601)
      expect(CGI.unescapeHTML(response.body)).to include("Already paid, and staying paid", "Ana Diaz, $100.00", "Ben Lee, $100.00",
        "more owed goes on the next payout run", "anything overpaid comes out of their next pay")
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Hot Tix sent more" }
      expect(payout.reload.line_items.map(&:paid?)).to eq([ true, true ])

      # The show took more: it can be worked out again, and the paid lines stand.
      travel 2.seconds
      show.show_financials.update!(ticket_revenue: 260.0)
      get manage_money_settle_up_day_path(date.iso8601)
      expect(response.body).to include("The numbers changed since this was worked out", "$260.00 to 2 people", "Recalculate")
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      expect(flash[:notice]).to eq("Pavlov Show: $260.00 to 2 people.")
      lines = payout.reload.line_items.order(:id)
      expect(lines.map { |l| [ l.payee_name, l.amount.to_f, l.paid?, l.correction? ] }).to contain_exactly(
        [ "Ana Diaz", 100.0, true, false ], [ "Ben Lee", 100.0, true, false ], [ "Ana Diaz", 30.0, false, true ], [ "Ben Lee", 30.0, false, true ])
      expect(org.payout_balance_cents_for(ana, category: "performer")).to eq(3000)

      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("$260.00 to 2 people", "Paid $100.00. $30.00 more goes on the payout run when the day settles.", "$60.00 for 2 people goes on the payout run")

      # Settling again puts only the difference on the new draft run.
      settle_day!
      expect(flash[:notice]).to include("$60.00 for 2 people went on the draft payout run")
      second_run = PayoutBatch.current_open_draft(org)
      expect(second_run).not_to eq(first_run)
      expect(second_run.items.find_by(payee: ana).amount_cents).to eq(3000)
      expect(second_run.payout_contributions.pluck(:label).uniq).to eq([ "#{show.name_with_date} (correction)" ])
      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      expect(CGI.unescapeHTML(response.body)).to include("Paid $100.00. $30.00 more is on the draft payout run.")

      # Reopened again before that run is submitted: the corrections come back off, the paid lines stay.
      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "One more look" }
      expect(flash[:notice]).to include("$60.00 for 2 people came off the draft payout run")
      expect(PayoutContribution.where(source: payout.line_items.where.not(correction_of_id: nil))).not_to exist
      expect(first_run.reload.payout_contributions.count).to eq(2)
    end

    it "takes what was overpaid out of the person's next pay" do
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      settle_day!
      submit_and_pay!(PayoutBatch.current_open_draft(org))
      payout = show.reload.show_payout

      post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "A refund came in" }
      travel 2.seconds
      show.show_financials.update!(ticket_revenue: 160.0)
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      expect(payout.reload.line_items.where.not(correction_of_id: nil).map { |l| [ l.payee_name, l.amount.to_f ] }).to contain_exactly([ "Ana Diaz", -20.0 ], [ "Ben Lee", -20.0 ])
      expect(org.payout_balance_cents_for(ana, category: "performer")).to eq(-2000)

      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("$160.00 to 2 people", "Overpaid $20.00", "Paid $100.00. The $20.00 over comes out of their next pay.")
      expect(body).not_to include("goes on the payout run when the day settles")

      # Nothing rides the run for this day: there is nothing more to pay.
      settle_day!
      expect(flash[:notice]).not_to include("went on the draft payout run")
      expect(PayoutBatch.current_open_draft(org)).to be_nil

      # Their next show pays them that much less.
      later = create(:show, production: production, date_and_time: 1.day.ago.change(hour: 20))
      create(:show_financials, show: later, ticket_count: 10, ticket_revenue: 100.0, expenses: 0)
      create(:show_person_role_assignment, show: later, assignable: ana)
      later_date = SettlementDay.day_for(org, later.date_and_time)
      patch manage_calculate_show_money_settle_up_day_path(later_date.iso8601, show_id: later.id)
      patch manage_check_show_money_settle_up_day_path(later_date.iso8601, show_id: later.id), params: { checked: "1" }
      post manage_settle_money_settle_up_day_path(later_date.iso8601)
      run = PayoutBatch.current_open_draft(org)
      expect(run.payout_contributions.find_by(payee: ana).amount_cents).to eq(10_000)
      expect(run.items.find_by(payee: ana).amount_cents).to eq(8000)

      submit_and_pay!(run)
      expect(org.payout_balance_cents_for(ana, category: "performer")).to eq(0)
      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      expect(CGI.unescapeHTML(response.body)).to include("The $20.00 over came out of their next pay.")
    end

    it "records a line paid another way from the day, and a hand edit to the money darkens the mark" do
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      line = show.reload.show_payout.line_items.find_by(payee: ana)
      post manage_mark_line_item_paid_money_show_payout_path(show, line_item_id: line.id), params: { payment_method: "cash", payment_notes: "At the door", return_to: manage_money_settle_up_day_path(date.iso8601) }
      expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601))
      expect(line.reload).to be_paid
      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      expect(response.body).to include("1 paid", "Paid another way · Cash", "$100.00 for 1 person goes on the payout run")

      patch manage_update_money_show_financials_path(show), params: { return_to: manage_money_settle_up_day_path(date.iso8601), show_financials: { other_revenue: "25" } }
      expect(show.reload.show_financials.data_confirmed).to be(false)
    end

    it "changes who's paid and how from the day: a different calculation, everyone the same amount, someone taken off and the missing cast put back, each line keeping its choice" do
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      payout = show.reload.show_payout
      ben_line = payout.line_items.find_by(payee: ben)
      patch manage_pay_line_money_settle_up_day_path(date.iso8601, show_id: show.id, line_id: ben_line.id), params: { pay_choice: "hold" }

      get manage_money_settle_up_day_path(date.iso8601, open: show.id)
      expect(response.body).to include("Use the calculation", "Even split", "Choose a different calculation", "Everyone the same amount", "Each person their own amount", "The people", "Remove")

      # Everyone the same amount, from the day: saved, worked out again, and Ben's hold kept.
      back = manage_money_settle_up_day_path(date.iso8601, open: show.id)
      patch manage_save_override_money_show_payout_path(show), params: { return_to: back, customize: { mode: "same", amount: "40" } }
      expect(response).to redirect_to(back)
      expect(payout.reload.line_items.map { |l| [ l.payee_name, l.amount.to_f, l.pay_choice ] }).to contain_exactly([ "Ana Diaz", 40.0, "run" ], [ "Ben Lee", 40.0, "hold" ])
      get back
      expect(response.body).to include("customized for this show")

      patch manage_save_override_money_show_payout_path(show), params: { return_to: back, customize: { mode: "calculation" } }
      expect(response).to redirect_to(back)
      expect(flash[:notice]).to include("pays as Even split says")
      expect(payout.reload.line_items.find_by(payee: ben).amount.to_f).to eq(100.0)

      # A different calculation for just this show, chosen from the day: worked out again on it.
      flat = create(:payout_scheme, organization: org, production: nil, name: "Flat $25", rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 25 } })
      patch manage_choose_calculation_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { choice: "existing", payout_scheme_id: flat.id, scope: "show", reopen: "pay-modal-#{show.id}" }
      expect(response).to redirect_to(manage_money_settle_up_day_path(date.iso8601, open: show.id, modal: "pay-modal-#{show.id}"))
      expect(flash[:notice]).to include("Pavlov Show uses Flat $25", "$50.00 to 2 people")
      get manage_money_settle_up_day_path(date.iso8601, open: show.id, modal: "pay-modal-#{show.id}")
      expect(response.body).to include(%(id="pay-modal-#{show.id}" class=" fixed inset-0))
      expect(payout.reload.line_items.map { |l| [ l.amount.to_f, l.pay_choice ] }).to contain_exactly([ 25.0, "run" ], [ 25.0, "hold" ])

      # Taken off from the day, and put back with the missing cast.
      delete manage_remove_line_item_money_show_payout_path(show, line_item_id: payout.line_items.find_by(payee: ben).id), params: { return_to: back }
      expect(response).to redirect_to(back)
      expect(payout.reload.line_items.count).to eq(1)
      get back
      expect(response.body).to include("Ben Lee is cast but not on the payout")
      post manage_add_missing_cast_money_show_payout_path(show), params: { return_to: back, amount: "30" }
      expect(response).to redirect_to(back)
      expect(payout.reload.line_items.find_by(payee: ben).amount.to_f).to eq(30.0)
    end

    it "keeps a show whose day isn't settled off the Money hub's To pay list, and the old pages point at the day" do
      patch manage_calculate_show_money_settle_up_day_path(date.iso8601, show_id: show.id)
      patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
      get manage_money_payouts_path
      expect(response.body).not_to include("1 payee to pay")

      get manage_money_show_payout_path(show)
      expect(response.body).to include("go on the payout run when", "Settle up #{date.strftime('%b %-d')}")
      expect(response.body).not_to include("Add to payout run")
    end
  end
end

# A contract show's settlement that was already paid when its day was
# reopened (Tim, 2026-11-04): it stays as paid, and the difference is a
# correction on the contract. More owed rides the next run; overpaid comes
# out of their next share.
RSpec.describe "Manage::SettlementDays corrects a paid contract settlement", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "calendar", settle_up_starts_on: Date.current - 30) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Witches") }
  let(:person) { create(:person, name: "Wanda West", stripe_account_id: "acct_w", payouts_enabled: true) }
  let(:contractor) { create(:contractor, organization: org, person: person, name: "Windy City Witches") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: contractor.name,
                               draft_data: { "payment_structure" => "revenue_share",
                                             "payment_config" => { "revenue_our_share" => 50, "revenue_their_share" => 50, "revenue_settlement" => "per_event" } })
  end
  let!(:show) { create(:show, production: production, date_and_time: 2.days.ago.change(hour: 20)) }
  let(:date) { SettlementDay.day_for(org, show.date_and_time) }
  let!(:share) do
    create(:show_financials, show: show, ticket_count: 48, ticket_revenue: 480.0, expenses: 0)
    create(:contract_payment, :outgoing, contract: contract, show: show, description: "50% to them", amount: 240, due_date: date,
                                         notes: "Auto-calculated from show financials:")
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def settle_day!
    patch manage_check_show_money_settle_up_day_path(date.iso8601, show_id: show.id), params: { checked: "1" }
    post manage_settle_money_settle_up_day_path(date.iso8601)
  end

  def submit_and_pay!(run)
    run.update!(status: "completed")
    run.items.each do |item|
      item.mark_paid!(transfer_id: "tr_#{item.id}")
      PayoutBatchService.settle_item_sources!(item, "tr_#{item.id}")
    end
  end

  it "puts more owed on the next run, and takes what was paid over out of their next share" do
    settle_day!
    expect(flash[:notice]).to include("$240.00 for 1 person went on the draft payout run")
    submit_and_pay!(PayoutBatch.current_open_draft(org))
    expect(share.reload).to be_status_paid

    get manage_money_settle_up_day_path(date.iso8601)
    expect(CGI.unescapeHTML(response.body)).to include("Already paid, and staying paid", "Windy City Witches, $240.00")

    # Reopened, and Hot Tix sent more: their half is $260 now.
    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "Hot Tix sent more" }
    show.show_financials.update!(ticket_revenue: 520.0)
    expect(share.reload.amount.to_f).to eq(240.0)
    get manage_money_settle_up_day_path(date.iso8601, open: show.id)
    expect(CGI.unescapeHTML(response.body)).to include("Ticket sales now make it $20.00 more, which goes on the payout run when the day settles.")

    settle_day!
    expect(flash[:notice]).to include("$20.00 for 1 person went on the draft payout run")
    more = share.corrections.sole
    expect(more).to have_attributes(direction: "outgoing", amount: 20.to_d, show_id: show.id, description: "Correction for #{show.date_and_time.strftime('%b %-d')}: more owed")
    expect(more.payout_contribution.payout_batch).to be_open
    expect(PayoutBatch.current_open_draft(org).total_cents).to eq(2_000)

    # Reopened before that run is submitted: the correction comes off and goes; the paid settlement stays.
    post manage_reopen_money_settle_up_day_path(date.iso8601), params: { reason: "A refund" }
    expect(share.reload.corrections).to be_empty
    expect(share).to be_status_paid
    expect(PayoutContribution.where(payee: person).where.not(source: share)).not_to exist

    # Now a refund: their half is $220, so $20 was paid over.
    show.show_financials.update!(ticket_revenue: 440.0)
    get manage_money_settle_up_day_path(date.iso8601, open: show.id)
    expect(CGI.unescapeHTML(response.body)).to include("Ticket sales now make it $20.00 less, which comes out of their next share.")
    settle_day!
    expect(flash[:notice]).not_to include("went on the draft payout run")
    over = share.reload.corrections.sole
    expect(over).to have_attributes(direction: "incoming", settlement_method: "payout_deduction", amount: 20.to_d, status: "pending")
    get manage_money_settle_up_day_path(date.iso8601, open: show.id)
    expect(CGI.unescapeHTML(response.body)).to include("$20.00 paid over comes out of their next share.")

    # Their next share on the contract pays that much less.
    next_share = create(:contract_payment, :outgoing, contract: contract, description: "Next night", amount: 100, due_date: Date.current)
    ContractorPayoutRunService.add_contract_payment!(next_share)
    run = PayoutBatch.current_open_draft(org)
    expect(run.items.find_by(payee: person).amount_cents).to eq(8_000)
    expect(over.reload).to be_status_paid
    get manage_money_settle_up_day_path(date.iso8601, open: show.id)
    expect(CGI.unescapeHTML(response.body)).to include("$20.00 paid over came out of a later share.")
  end
end

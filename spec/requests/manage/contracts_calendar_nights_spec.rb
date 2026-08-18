# frozen_string_literal: true

require "rails_helper"

# The contracts calendar answers "how did Friday do?" for a night that has
# happened: one bar with what the night made us all in — the tickets we sold,
# less what we handed the contractor, plus what they paid us — instead of a
# pile of signed payment pills. Nights still ahead show no numbers at all.
RSpec.describe "Manage::Contracts calendar nights", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Random Memory") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def month_param(date) = date.strftime("%Y-%m-01")

  # A night in the same month as today that has already happened; a night still
  # to come in the same month when there is one, else next month.
  let(:past_at) { (Date.current.day > 3 ? 2.days.ago : Date.current.beginning_of_month.to_time).change(hour: 20) }
  let(:future_at) { 3.days.from_now.change(hour: 20) }

  context "a revenue split where we sell" do
    let!(:contract) do
      create(:contract, :active, organization: org, production: production, contractor_name: "Dan",
                        draft_data: { "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                                                            "revenue_our_share" => 50, "revenue_settlement" => "per_event" } })
    end
    let!(:show) { create(:show, production: production, date_and_time: past_at) }
    let!(:settlement) do
      create(:contract_payment, contract: contract, direction: "outgoing", show: show,
                                description: "Revenue Share", amount: 100, due_date: past_at.to_date)
    end

    before { create(:show_financials, :complete, show: show, ticket_revenue: 200, expenses: 0) }

    it "shows one bar with what the night made us, and folds the settlement into it" do
      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response).to have_http_status(:ok)

      expect(response.body).to include(">$100<")
      # No rental card for this show, so the bar reads like a booking: time · name
      expect(response.body).to include("#{past_at.strftime('%-l:%M%p').downcase} · Random Memory")
      expect(response.body).to include("Random Memory: $100 · Ticket sales: +$200 · Paid Dan: −$100")
      # The −$100 settlement doesn't also show as its own pill
      expect(response.body).not_to include(">−$100<")
      # The settled $100 is past due and unpaid — that IS late
      expect(response.body).to include('text-red-600">Late')
    end

    it "rides on the rental card when the booking is on the calendar, instead of a second bar" do
      rental = create(:space_rental, contract: contract, starts_at: past_at)
      show.update!(space_rental: rental)

      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response.body.scan(">$100<").size).to eq(1)
      expect(response.body).to include("Space rental")
      expect(response.body).not_to include("#{past_at.strftime('%-l:%M%p').downcase} · Random Memory</div>")
    end

    it "isn't 'late' while the settlement is only TBD" do
      # Numbers withdrawn: the settlement goes back to TBD (financials sync it, so order matters)
      show.show_financials.destroy!
      settlement.reload.update!(amount: 0, amount_tbd: true)
      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response.body).to include("Needs financials")
      expect(response.body).not_to include('text-red-600">Late')
    end

    it "says the numbers aren't in yet for a past night without financials" do
      other = create(:show, production: production, date_and_time: past_at - 1.hour)
      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response.body).to include("Needs financials")
      expect(response.body).to include(manage_money_show_financials_path(other))
    end
  end

  context "a minus-fee deal" do
    let!(:contract) do
      create(:contract, :active, organization: org, production: production,
                        draft_data: { "payment_structure" => "flat_fee",
                                      "payment_config" => { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 300,
                                                            "flat_fee_basis" => "per_show", "flat_fee_settlement" => "per_event" } })
    end

    it "reads as our fee when the night cleared it, and puts no money on a night still ahead" do
      past_show = create(:show, production: production, date_and_time: past_at)
      create(:contract_payment, contract: contract, direction: "outgoing", show: past_show,
                                description: "Ticket revenue less $300.00 fee", amount: 500, due_date: past_at.to_date)
      create(:show_financials, :complete, show: past_show, ticket_revenue: 800, expenses: 0)

      future_show = create(:show, production: production, date_and_time: future_at)
      create(:contract_payment, contract: contract, direction: "outgoing", show: future_show,
                                description: "Ticket revenue less $300.00 fee", amount: 0, amount_tbd: true, due_date: future_at.to_date)

      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response.body).to include(">$300<")
      expect(response.body).to include("Ticket sales: +$800 · Paid Venue Corp: −$500")
      expect(response.body).not_to include(">−$500<")

      get manage_contracts_path(month: month_param(future_at.to_date))
      expect(response.body).not_to include("TBD")
      expect(response.body).not_to include("Settles after the show")
    end
  end

  context "a booking still ahead" do
    let!(:contract) do
      create(:contract, :active, organization: org, production: production, contractor_name: "Dan",
                        draft_data: { "payment_structure" => "flat_fee",
                                      "payment_config" => { "flat_fee_direction" => "incoming", "flat_fee_amount" => 60,
                                                            "flat_fee_basis" => "per_show", "flat_fee_settlement" => "per_event" } })
    end

    it "shows the rental alone — the fee due that night and the settlement stay off the card until the day comes" do
      rental = create(:space_rental, contract: contract, starts_at: future_at)
      future_show = create(:show, production: production, date_and_time: future_at, space_rental: rental)
      create(:contract_payment, contract: contract, direction: "incoming", show: future_show,
                                description: "Flat fee", amount: 60, due_date: future_at.to_date)
      create(:contract_payment, contract: contract, direction: "outgoing", show: future_show,
                                description: "Settlement", amount: 0, amount_tbd: true, due_date: future_at.to_date)
      # A deposit due on a day that hasn't come stays off the calendar too
      create(:contract_payment, contract: contract, direction: "incoming",
                                description: "Deposit", amount: 500, due_date: future_at.to_date)

      get manage_contracts_path(month: month_param(future_at.to_date))
      expect(response.body).to include("Space rental")
      expect(response.body).not_to include("+$60")
      expect(response.body).not_to include("$500")
      expect(response.body).not_to include("TBD")
      expect(response.body).not_to include("Settles after the show")
    end

    it "shows the fee on the card once the night has come, but never spells out TBD" do
      rental = create(:space_rental, contract: contract, starts_at: past_at)
      create(:contract_payment, contract: contract, direction: "incoming",
                                description: "Rent", amount: 60, due_date: past_at.to_date)
      create(:contract_payment, contract: contract, direction: "outgoing",
                                description: "Settlement", amount: 0, amount_tbd: true, due_date: past_at.to_date)

      get manage_contracts_path(month: month_param(past_at.to_date))
      expect(response.body).to include("+$60")
      expect(response.body).not_to include("TBD")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# The hub summarises three pages. If its numbers can drift from theirs, it's
# worse than no hub — you'd stop trusting the page you landed on. These specs
# assert the agreement, page against page.
RSpec.describe "Money hub parity", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Parity Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def links_to(path) = response.body.include?(%(href="#{path}"))

  describe "shows needing financials" do
    let!(:overdue_a) { create(:show, production: production, event_type: :show, date_and_time: 2.days.ago) }
    let!(:overdue_b) { create(:show, production: production, event_type: :show, date_and_time: 4.days.ago) }
    # Neither of these is work: one hasn't happened, one never will.
    let!(:starts_soon) { create(:show, production: production, event_type: :show, date_and_time: 6.hours.from_now) }
    let!(:canceled) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago, canceled: true) }

    it "offers the same shows on the hub as on the Financials page" do
      get manage_money_index_path
      hub = [ overdue_a, overdue_b, starts_soon, canceled ]
             .select { |s| links_to(manage_money_show_financials_path(s)) }

      get manage_money_financials_path
      page = [ overdue_a, overdue_b, starts_soon, canceled ]
              .select { |s| links_to(manage_money_show_financials_path(s)) }

      expect(hub).to contain_exactly(overdue_a, overdue_b)
      expect(page).to eq(hub)
    end

    # The per-production counts on /all used a later cutoff than the index, so a
    # show starting in six hours was pending on one page and not the other.
    it "agrees with the pending filter on All Financials" do
      get manage_money_all_financials_path(filter: "pending")
      expect(response.body).to include("Parity Revue")

      [ overdue_a, overdue_b ].each { |s| create(:show_financials, :complete, show: s, ticket_revenue: 10.0) }

      get manage_money_all_financials_path(filter: "pending")
      expect(response.body).not_to include("Parity Revue")

      get manage_money_index_path
      expect(response.body).to include("You&#39;re all caught up on financials.")
    end

    it "drops a show from the hub as soon as its financials are confirmed" do
      get manage_money_index_path
      expect(links_to(manage_money_show_financials_path(overdue_a))).to be(true)

      create(:show_financials, :complete, show: overdue_a, ticket_revenue: 200.0)

      get manage_money_index_path
      expect(links_to(manage_money_show_financials_path(overdue_a))).to be(false)
    end
  end

  describe "money still to pay" do
    let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
    let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 150) }
    let!(:paid) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 70) }
    let!(:unpaid_a) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 50) }
    let!(:unpaid_b) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 30) }

    before { paid.update_columns(manually_paid: true, manually_paid_at: Time.current) }

    it "shows the same outstanding total as the Payouts page" do
      get manage_money_index_path
      expect(response.body).to include("Parity Revue")
      expect(response.body).to include("$80.00 still unpaid")   # not the $150 gross

      get manage_money_payouts_path
      expect(response.body).to include("$80.00 still unpaid in total")
    end
  end

  describe "money owed to us" do
    let!(:contract) { create(:contract, organization: org, production: production) }

    def incoming!(due_date:, settlement_method: "direct")
      ContractPayment.create!(contract: contract, direction: "incoming", status: "pending",
                              amount: 100, due_date: due_date, description: "Fee",
                              settlement_method: settlement_method)
    end

    let!(:late) { incoming!(due_date: 5.days.ago.to_date) }
    let!(:soon) { incoming!(due_date: 12.days.from_now.to_date) }
    let!(:later) { incoming!(due_date: 60.days.from_now.to_date) }

    # The hub looks 30 days ahead; Incoming defaults to three months. The window
    # param on the link is the only thing making the two agree.
    it "links Incoming with the window that reproduces the hub's list" do
      get manage_money_index_path
      expect(links_to(manage_money_incoming_payment_path(late))).to be(true)
      expect(links_to(manage_money_incoming_payment_path(soon))).to be(true)
      expect(links_to(manage_money_incoming_payment_path(later))).to be(false)
      expect(response.body).to include(manage_money_incoming_path(window: "1m"))

      get manage_money_incoming_path(window: "1m")
      expect(links_to(manage_money_incoming_payment_path(late))).to be(true)
      expect(links_to(manage_money_incoming_payment_path(soon))).to be(true)
      expect(links_to(manage_money_incoming_payment_path(later))).to be(false)
    end

    it "leaves deduction-settled charges off both" do
      deducted = incoming!(due_date: 3.days.from_now.to_date, settlement_method: "payout_deduction")

      get manage_money_index_path
      expect(links_to(manage_money_incoming_payment_path(deducted))).to be(false)

      get manage_money_incoming_path(window: "1m")
      expect(links_to(manage_money_incoming_payment_path(deducted))).to be(false)
    end
  end

  describe "truncation" do
    let!(:shows) do
      7.times.map { |i| create(:show, production: production, event_type: :show, date_and_time: (i + 1).days.ago) }
    end

    it "renders five rows but counts and offers all seven" do
      get manage_money_index_path

      shown = shows.count { |s| links_to(manage_money_show_financials_path(s)) }
      expect(shown).to eq(5)
      expect(response.body).to include("See all 7 in Financials")

      # The page it points at holds the rest.
      get manage_money_financials_path
      expect(shows.count { |s| links_to(manage_money_show_financials_path(s)) }).to eq(7)
    end
  end
end

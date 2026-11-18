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

  # Books V1.3: the hub's first section is the days to settle (SettleUp), not
  # a list of shows needing financials. A day appears once it has ended with
  # money in it and nobody has settled it; the Settle up page lists the same.
  describe "days to settle" do
    let!(:overdue_a) { create(:show, production: production, event_type: :show, date_and_time: 2.days.ago) }
    let!(:overdue_b) { create(:show, production: production, event_type: :show, date_and_time: 4.days.ago) }
    # Neither of these is work: one hasn't happened, one never will.
    let!(:starts_soon) { create(:show, production: production, event_type: :show, date_and_time: 6.hours.from_now) }
    let!(:canceled) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago, canceled: true) }

    def day_path(show) = manage_money_settle_up_day_path(SettlementDay.day_for(org, show.date_and_time).iso8601)

    def settle!(show)
      create(:show_financials, :complete, show: show, ticket_revenue: 100.0)
      SettlementDay.create!(organization: org, date: SettlementDay.day_for(org, show.date_and_time)).settle!(by: owner)
    end

    it "offers the same days on the hub as on the Settle up page" do
      get manage_money_index_path
      hub = [ overdue_a, overdue_b, starts_soon, canceled ].select { |s| links_to(day_path(s)) }
      expect(hub).to contain_exactly(overdue_a, overdue_b)
      expect(response.body).to include("2 days to settle up")

      get manage_money_settle_up_path
      expect([ overdue_a, overdue_b ].select { |s| links_to(day_path(s)) }).to eq(hub)
      expect(links_to(day_path(canceled))).to be(false)
    end

    it "says every day is settled once they are, on the hub and on Settle up" do
      settle!(overdue_a)
      settle!(overdue_b)

      # (The show later today hasn't started, so today isn't on the list yet.)
      get manage_money_index_path
      expect(response.body).to include("Every day is settled.")
      expect(links_to(day_path(overdue_a))).to be(false)

      get manage_money_settle_up_path
      expect(response.body).to include("Every day is settled", "The next show that happens will put its day here.")
      expect(response.body).not_to include("data-settle-today")
      expect(links_to(day_path(overdue_a))).to be(false)
    end

    # Once a show of today's has started, Settle up has its Today box and the
    # line is about the days before it.
    it "says every earlier day is settled once today is under way" do
      settle!(overdue_a)
      settle!(overdue_b)
      create(:show, production: production, event_type: :show, date_and_time: 1.minute.ago)

      get manage_money_settle_up_path
      expect(response.body).to include("data-settle-today", "Every earlier day is settled.")
    end

    # The hub lists today while it's still going (Tim, 2026-11-13: it said
    # "Every day is settled" with a night in progress), first and marked,
    # without calling it a day to settle up.
    it "lists today first on the hub while it's still going, and never says every day is settled over it" do
      settle!(overdue_a)
      settle!(overdue_b)
      tonight = create(:show, production: production, event_type: :show, date_and_time: 1.minute.ago)

      get manage_money_index_path
      expect(links_to(day_path(tonight))).to be(true)
      expect(response.body).to include("today, still going")
      expect(response.body).not_to include("Every day is settled.", "day to settle up", "days to settle up")
    end

    it "drops a day from the hub as soon as it is settled" do
      get manage_money_index_path
      expect(links_to(day_path(overdue_a))).to be(true)

      settle!(overdue_a)

      get manage_money_index_path
      expect(links_to(day_path(overdue_a))).to be(false)
      expect(links_to(day_path(overdue_b))).to be(true)
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
      # The card names stages, never one "unpaid in all" that folds in money
      # already on a run (Tim, 2026-11-11).
      expect(response.body).to include("$80.00 due now", "Nothing else is waiting.")
      expect(response.body).not_to include("unpaid in all")

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

    def day_path(show) = manage_money_settle_up_day_path(SettlementDay.day_for(org, show.date_and_time).iso8601)

    it "renders five days but counts and offers all seven" do
      get manage_money_index_path

      expect(shows.count { |s| links_to(day_path(s)) }).to eq(5)
      expect(response.body).to include("7 days to settle up", "See all 7 in Settle up")

      # The page it points at holds the rest.
      get manage_money_settle_up_path
      expect(shows.count { |s| links_to(day_path(s)) }).to eq(7)
    end
  end
end

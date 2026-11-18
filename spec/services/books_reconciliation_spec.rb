# frozen_string_literal: true

require "rails_helper"

# The books must agree with the records they summarize: ticket money in the
# cash ledger, and tax on paid tickets. A missed posting shows up here.
RSpec.describe BooksReconciliation do
  let(:org) { create(:organization, :pro, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  def sold(count)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(3)}")
    order.reload
  end

  it "agrees through sales, refunds, door cash, disputes and withdrawals" do
    open_every_door!
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_1"))

    order = sold(3)
    sold(2)
    TicketOrderRefund.issue!(order, ticket_ids: [ order.tickets.first.id ])
    TicketDoor.new(listing, create(:user)).sell({ general.id.to_s => "2" }, kind: "cash")
    TicketDispute.opened!(sold(1), 2_255)
    travel_to(listing.show.date_and_time + 3.days) do
      TicketMoneyReleaseJob.perform_now
      BalanceWithdrawalService.withdraw!(org, amount_cents: 1_000)
    end

    expect(described_class.check(org)).to eq([])
  end

  # A show still ahead has presales Financials count that the books hold as
  # tickets sold for upcoming shows: compared through today, they agree.
  it "compares Financials with Books through today" do
    travel_to(Time.zone.local(2026, 11, 15, 12)) do
      production = listing.production
      listing.show.update!(date_and_time: 3.days.from_now)
      sold(2)
      expect(described_class.financials_vs_books(org, period_key: "this_month")).to be_empty

      past = create(:show, production: production, date_and_time: 2.days.ago)
      ShowFinancials.create!(show: past, revenue_type: "ticket_sales", ticket_revenue: 999, ticket_count: 9)
      LedgerPosting.unpost!(source: past.show_financials, kind: "outside_tickets")
      row = described_class.financials_vs_books(org, period_key: "this_month").sole
      expect([ row.production, row.financials_in_cents, row.books_in_cents ]).to eq([ production, 99_900, 0 ])
    end
  end

  # Tonight's show is in the period, and its presales wait on the books
  # until 4am tomorrow: not a disagreement (Tim, 2026-11-11).
  it "doesn't list a show whose ticket money is still waiting to be counted" do
    travel_to(Time.zone.local(2026, 11, 15, 12)) do
      listing.show.update!(date_and_time: Time.current.change(hour: 19))
      sold(2)
      expect(described_class.financials_vs_books(org, period_key: "this_month")).to be_empty
    end

    # The show has started: Financials count its $40, the books still hold it.
    travel_to(Time.zone.local(2026, 11, 15, 21)) do
      expect(described_class.financials_vs_books(org, period_key: "this_month")).to be_empty
      expect(described_class.waiting_on_shows_in(org, BooksReport.period_range("this_month"))).to eq(listing.production.id => 4_000)
    end

    travel_to(Time.zone.local(2026, 11, 16, 12)) do
      TicketMoneyReleaseJob.perform_now
      expect(described_class.financials_vs_books(org, period_key: "this_month")).to be_empty
      expect(described_class.waiting_on_shows_in(org, BooksReport.period_range("this_month"))).to be_empty
    end
  end

  it "notices a sale that never reached the books" do
    order = sold(1)
    LedgerPosting.unpost!(source: order, kind: "sale")

    mismatch = described_class.check(org).find { |m| m.account == "cocoscout_balance" }
    expect([ mismatch.books_cents, mismatch.expected_cents, mismatch.difference_cents ]).to eq([ 0, 2_000, -2_000 ])
    expect(Rails.logger).to receive(:error).with(/org #{org.id} cocoscout_balance/).at_least(:once)
    BooksReconciliationJob.perform_now
  end

  # The nightly check tells CocoScout's superadmins (Tim, 2026-11-09): a
  # notification, no email, once for each thing it finds, whose own page
  # says whose books and which account.
  describe "telling the superadmins" do
    let!(:superadmin) { create(:user, email_address: User::SUPERADMIN_EMAILS.first) }
    let!(:someone_else) { create(:user) }
    let(:balance) { ChartOfAccounts::SYSTEM.dig(:cocoscout_balance, :name) }

    def told = superadmin.notifications.where(kind: "books_check_mismatch").order(:id)

    it "says nothing while every organization's books agree" do
      sold(1)
      expect { BooksReconciliationJob.perform_now }.not_to(change { Notification.count })
    end

    it "tells them once when books stop agreeing, with the organization and the account, and no email" do
      order = sold(1)
      LedgerPosting.unpost!(source: order, kind: "sale")

      expect { BooksReconciliationJob.perform_now }.to change { told.count }.by(1).and(not_change { ActionMailer::Base.deliveries.size })
      notice = told.last
      expect(notice.title).to eq("Books check: #{org.name}, #{balance} off by $20.00")
      expect(notice.category).to eq("books")
      # A tap opens the notice's own words.
      expect(notice.path).to be_nil
      expect(notice.body).to include(org.name, "/superadmin/organizations/#{org.id}", "#{balance}: books say $0.00, records say $20.00 (off by $20.00)", "Nothing was changed")
      expect(someone_else.notifications).to be_empty

      # The same disagreement the next night is not news.
      expect { BooksReconciliationJob.perform_now }.not_to(change { told.count })
    end

    it "tells them again when it changes, and again if it comes back after being put right" do
      first = sold(1)
      LedgerPosting.unpost!(source: first, kind: "sale")
      BooksReconciliationJob.perform_now

      second = sold(2)
      LedgerPosting.unpost!(source: second, kind: "sale")
      expect { BooksReconciliationJob.perform_now }.to change { told.count }.by(1)
      expect(told.last.title).to include("off by $60.00")

      # Put right: nothing to say, and the slate is clean.
      allow(BooksReconciliation).to receive(:check).and_return([])
      expect { BooksReconciliationJob.perform_now }.not_to(change { told.count })
      allow(BooksReconciliation).to receive(:check).and_call_original
      expect { BooksReconciliationJob.perform_now }.to change { told.count }.by(1)
    end

    it "is still news that night when a page ran the checks during the day" do
      order = sold(1)
      LedgerPosting.unpost!(source: order, kind: "sale")
      # Books → Checks keeps what it found, for the organization's pages.
      BooksReconciliation.record!(org)
      expect { BooksReconciliationJob.perform_now }.to change { told.count }.by(1)
      # And a page running them afterwards doesn't make it news again.
      BooksReconciliation.record!(org)
      expect { BooksReconciliationJob.perform_now }.not_to(change { told.count })
    end

    it "names how many organizations when more than one disagrees" do
      other = create(:organization, :pro, name: "Second House")
      off = ->(account, cents) { BooksReconciliation::Mismatch.new(account: account, books_cents: cents, expected_cents: 0) }
      BooksNotices.books_disagree([ [ org, [ off.call("cocoscout_balance", 2_000), off.call("tax_to_remit", 150) ] ], [ other, [ off.call("tax_to_remit", 500) ] ], [ create(:organization), [] ] ])
      expect(told.last.title).to eq("Books check: 2 organizations' books don't agree with their records")
      expect(told.last.body).to include(org.name, "Second House", "/superadmin/organizations/#{other.id}", "off by $5.00")

      BooksNotices.books_disagree([ [ org, [ off.call("cocoscout_balance", 2_000), off.call("tax_to_remit", 150) ] ] ])
      expect(told.last.title).to eq("Books check: #{org.name}, #{balance} off by $20.00 and 1 more")
    end

    it "stays quiet on a laptop, whose copy of production never agrees for long" do
      order = sold(1)
      LedgerPosting.unpost!(source: order, kind: "sale")
      allow(Rails.env).to receive(:development?).and_return(true)
      expect { BooksReconciliationJob.perform_now }.not_to(change { told.count })
    end
  end
end

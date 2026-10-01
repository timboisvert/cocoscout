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

  it "notices a sale that never reached the books" do
    order = sold(1)
    LedgerPosting.unpost!(source: order, kind: "sale")

    mismatch = described_class.check(org).find { |m| m.account == "cocoscout_balance" }
    expect([ mismatch.books_cents, mismatch.expected_cents, mismatch.difference_cents ]).to eq([ 0, 2_000, -2_000 ])
    expect(Rails.logger).to receive(:error).with(/org #{org.id} cocoscout_balance/).at_least(:once)
    BooksReconciliationJob.perform_now
  end
end

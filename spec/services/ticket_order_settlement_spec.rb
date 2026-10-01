# frozen_string_literal: true

require "rails_helper"

# A ticket order's money arrived: real tickets, the theater's balance, the
# books, the show's financials and the buyer's email — once, however many
# times Stripe or the buyer's browser report it.
RSpec.describe TicketOrderSettlement do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def checkout(count = 2)
    TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
  end

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  it "makes the tickets real and puts the money where it belongs" do
    order = checkout
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    expect { described_class.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1") }
      .to have_enqueued_job(TicketOrderConfirmationJob).with(order.id)

    order.reload
    expect([ order.status, order.stripe_payment_intent_id, order.tickets.pluck(:status).uniq ]).to eq([ "paid", "pi_1", [ "valid" ] ])

    # The theater's balance gets exactly its $40.
    expect(OrgCashEntry.where(source: order).pluck(:entry_type, :amount_cents)).to eq([ [ "ticket_sale", 4_000 ] ])

    # The books: $40 in the balance, held as sales for an upcoming show; the
    # buyer's $2.53 of fees exactly covers our 50¢ × 2 and processing.
    expect(balance(:cocoscout_balance)).to eq(4_000)
    expect(balance(:advance_ticket_sales)).to eq(4_000)
    expect(balance(:ticketing_fees) + balance(:fees_paid_by_buyers)).to eq(0)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

    # The show's financials: a CocoScout Tickets row, face value only.
    line = listing.show.reload.show_financials.ticket_sales_lines.sole
    expect([ line.ticket_source.name, line.ticket_source.system_key, line.tickets_sold, line.amount.to_f ])
      .to eq([ "CocoScout Tickets", "cocoscout", 2, 40.0 ])
    expect(listing.show.show_financials.reload.ticket_revenue.to_f).to eq(40.0)
  end

  it "settles only once" do
    order = checkout
    described_class.settle!(order, payment_intent_id: "pi_1")
    described_class.settle!(order.reload, payment_intent_id: "pi_1")

    expect(OrgCashEntry.where(source: order).count).to eq(1)
    expect(JournalEntry.live.where(source: order).count).to eq(1)
  end

  it "keeps tax out of revenue: it's owed to the government, and the books still balance" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "included")
    order = checkout(1)
    described_class.settle!(order)

    expect(balance(:tax_to_remit)).to eq(186)
    expect(balance(:advance_ticket_sales)).to eq(1_814)
    expect(listing.show.reload.show_financials.ticket_sales_lines.sole.amount.to_f).to eq(18.14)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(order.tickets.sole.tax_lines.sole.sale_date).to eq(Date.current)
  end

  it "absorbing the fees shows as a cost to the theater" do
    listing.update!(fee_mode: "org")
    order = checkout(1)
    described_class.settle!(order)

    expect(balance(:cocoscout_balance)).to eq(1_862)
    expect(balance(:ticketing_fees)).to eq(138)
    expect(balance(:fees_paid_by_buyers)).to eq(0)
  end

  it "honors a payment that arrives after the hold ran out, while the seats are still there" do
    order = checkout
    travel 15.minutes do
      ExpireTicketHoldsJob.perform_now
      described_class.settle!(order.reload, payment_intent_id: "pi_late")
    end
    expect(order.reload.status).to eq("paid")
  end

  it "refunds a late payment when its seats were sold to someone else" do
    general.update!(quantity: 2)
    late = checkout(2)
    allow(Stripe::Refund).to receive(:create)

    travel 15.minutes do
      other = checkout(2)
      described_class.settle!(other, payment_intent_id: "pi_other")
      described_class.settle!(late.reload, payment_intent_id: "pi_late")
    end

    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: "pi_late" }, hash_including(:idempotency_key))
    expect(late.reload.status).to eq("canceled")
    expect(late.tickets.pluck(:status).uniq).to eq([ "void" ])
    expect(OrgCashEntry.where(source: late)).to be_empty
  end

  it "settles a free order without touching money" do
    free = listing.ticket_tiers.create!(name: "Comp", price_cents: 0)
    order = TicketCheckout.start!(listing: listing, quantities: { free.id.to_s => "1" })
    described_class.settle!(order)

    expect(order.reload.status).to eq("paid")
    expect(OrgCashEntry.where(source: order)).to be_empty
    expect(JournalEntry.where(source: order)).to be_empty
  end
end

# frozen_string_literal: true

require "rails_helper"

# Credit passes (Tim, 2026-10-05): a punch card or a season pass, bought now,
# used later. The money is the organization's but held until the pass ends;
# each credit used counts price ÷ credits at its show; unused credits are the
# organization's income when the pass ends. The books, the balance and the
# Stripe check all agree throughout.
RSpec.describe TicketPassCredits do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Twilight") }
  let(:listing) { TicketListing.create!(show: create(:show, production: production, date_and_time: 10.days.from_now), status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let(:pass) do
    org.ticket_passes.create!(name: "Twilight Punch Card", kind: "punch_card", price_cents: 6_000, credits: 5, ends_on: 30.days.from_now.to_date,
                              status: "on_sale", coverages_attributes: [ { production_id: production.id } ])
  end

  before do
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .and_return(Stripe::PaymentIntent.construct_from(id: "pi_card", latest_charge: { balance_transaction: { fee: 220 } }))
  end

  def bought(the_pass = pass, intent: "pi_card")
    purchase = described_class.start!(pass: the_pass, quantity: 1)
    purchase.ticket_pass_holdings.update_all(holder_name: "Bella Swan", holder_email: "bella@example.com")
    perform_enqueued_jobs { TicketPurchaseSettlement.settle!(purchase.reload, payment_intent_id: intent) }
    purchase.ticket_pass_holdings.first.reload
  end

  it "sells a punch card with our fee per credit, holding its money until it ends" do
    holding = bought

    expect(holding.status).to eq("active")
    expect(holding.platform_fee_cents).to eq(250)
    expect(holding.org_net_cents).to eq(6_000)
    expect(holding.stripe_fee_cents).to eq(220)
    expect(OrgCashEntry.find_by(entry_type: "pass_sale").amount_cents).to eq(6_000)
    expect(TicketBalance.summary(org).upcoming_cents).to eq(6_000)
    expect(CocoScoutBalance.available_cents(org)).to eq(0)
    expect(BooksReconciliation.check(org)).to eq([])
    expect(ActionMailer::Base.deliveries.last.subject).to eq("Your Twilight Punch Card")
  end

  it "turns credits into a show's tickets, each counting the price ÷ credits" do
    holding = bought

    order = described_class.use!(holding, listing: listing, people: 2)
    expect(order.tickets.pluck(:price_cents, :discount_cents, :status)).to eq([ [ 2_000, 800, "valid" ] ] * 2)
    expect(holding.credits_left).to eq(3)
    expect(listing.inventory.remaining(tier: general)).to eq(8)
    expect(listing.show.reload.show_financials.ticket_sales_lines.pluck(:tickets_sold, :amount)).to eq([ [ 2, 24.to_d ] ])
    expect(ChartOfAccounts.account(org, :pass_credits_unused).natural_balance_cents).to eq(3_600)
    expect(BooksReconciliation.check(org)).to eq([])

    expect { described_class.use!(holding, listing: listing, people: 4) }.to raise_error(described_class::Error, /3 credits left/)
    expect { TicketOrderRefund.issue!(order) }.to raise_error(TicketOrderRefund::Error, /Refund the pass instead/)
  end

  it "gives a season pass one seat a show" do
    season = org.ticket_passes.create!(name: "Twilight Season", kind: "season", price_cents: 8_000, credits: 4, ends_on: 60.days.from_now.to_date,
                                       status: "on_sale", coverages_attributes: [ { production_id: production.id } ])
    holding = bought(season)

    described_class.use!(holding, listing: listing, people: 3)
    expect(holding.credits_left).to eq(3)
    expect { described_class.use!(holding, listing: listing) }.to raise_error(described_class::Error, /one seat a show/)
  end

  it "reminds the holder a week out, then ends it: unused credits become the organization's" do
    holding = bought
    described_class.use!(holding, listing: listing, people: 1)
    ActionMailer::Base.deliveries.clear

    travel_to((holding.ends_on - 3).in_time_zone) { TicketPassEndingJob.perform_now }
    expect(ActionMailer::Base.deliveries.map(&:subject)).to eq([ "Your Twilight Punch Card ends #{holding.ends_on.strftime('%B %-d, %Y')}" ])

    travel_to((holding.ends_on + 1).in_time_zone) { TicketPassEndingJob.perform_now }
    expect(holding.reload.status).to eq("ended")
    expect(ChartOfAccounts.account(org, :unused_pass_income).natural_balance_cents).to eq(4_800)
    expect(ChartOfAccounts.account(org, :pass_credits_unused).natural_balance_cents).to eq(0)
    expect(TicketBalance.summary(org).upcoming_cents).to eq(0)
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "refunds an unused pass in full, our fees given back and the processing the organization's, and never a used one" do
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_card"))
    holding = bought

    TicketPassCredits.refund!(holding)
    expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_card", amount: holding.total_cents), anything)
    expect(holding.reload.status).to eq("canceled")
    expect(OrgCashEntry.find_by(entry_type: "pass_refund").amount_cents).to eq(-(holding.total_cents - holding.platform_fee_cents))
    expect(TicketBalance.summary(org).upcoming_cents).to eq(0)
    expect(BooksReconciliation.check(org)).to eq([])
    category, record, = StripeTransactionMatcher.send(:refund, Struct.new(:source_id).new("re_card"), {})
    expect([ category, record ]).to eq([ "ticket_refund", holding ])

    used = bought(intent: "pi_second")
    described_class.use!(used, listing: listing)
    expect { TicketPassCredits.refund!(used) }.to raise_error(described_class::Error, /has been used/)
  end

  it "matches the Stripe charge to the pass, and refuses a show it doesn't cover" do
    holding = bought
    category, record, expected = StripeTransactionMatcher.send(:charge, { "payment_intent" => "pi_card" })
    expect([ category, record, expected ]).to eq([ "ticket_pass", holding, holding.ticket_purchase.total_cents ])

    other = TicketListing.create!(show: create(:show, production: create(:production, organization: org), date_and_time: 5.days.from_now), status: "on_sale")
    other.ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 5)
    expect { described_class.use!(holding, listing: other) }.to raise_error(described_class::Error, /doesn't cover/)
  end
end

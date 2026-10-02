# frozen_string_literal: true

require "rails_helper"

# Refunds: everything back by default, fees kept on request, our 50¢ never
# kept, tax off the report, the books still balanced, and never more than the
# theater's own money.
RSpec.describe TicketOrderRefund do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1")) }

  def sold(count, fee_mode: "buyer", intent: "pi_sale")
    listing.update!(fee_mode: fee_mode)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: intent)
    order.reload
  end

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  it "gives everything back by default, and the theater gives up all but our waived 50¢" do
    order = sold(1) # buyer paid $21.42; the theater kept $20.00

    refund = described_class.issue!(order)

    expect(Stripe::Refund).to have_received(:create)
      .with(hash_including(payment_intent: "pi_sale", amount: 2_142), hash_including(idempotency_key: "ticket-refund-#{refund.id}"))
    expect(refund.attributes.slice("amount_cents", "fees_cents", "platform_fee_waived_cents", "org_debit_cents"))
      .to eq("amount_cents" => 2_142, "fees_cents" => 142, "platform_fee_waived_cents" => 50, "org_debit_cents" => 2_092)
    expect([ order.reload.status, order.refunded_cents, order.tickets.pluck(:status) ]).to eq([ "refunded", 2_142, [ "refunded" ] ])
    expect(OrgCashEntry.balance_cents(org)).to eq(2_000 - 2_092)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(balance(:advance_ticket_sales)).to eq(0)
    expect(listing.show.reload.show_financials.ticket_sales_lines).to be_empty
    expect(TicketRefundEmailJob).to have_been_enqueued.with(refund.id)
  end

  it "keeps the fees when asked, still waiving our 50¢" do
    refund = described_class.issue!(sold(1), keep_fees: true)
    expect(refund.attributes.slice("amount_cents", "fees_cents", "org_debit_cents"))
      .to eq("amount_cents" => 2_000, "fees_cents" => 0, "org_debit_cents" => 1_950)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end

  it "refunds some tickets with their share of the fees, and the rest with what's left" do
    order = sold(2) # $42.53: $2.53 of fees
    first, second = order.tickets.order(:id).to_a

    one = described_class.issue!(order, ticket_ids: [ first.id ])
    expect([ one.amount_cents, one.fees_cents, order.reload.status ]).to eq([ 2_126, 126, "partially_refunded" ])
    expect(listing.show.reload.show_financials.ticket_sales_lines.sole.tickets_sold).to eq(1)

    two = described_class.issue!(order, ticket_ids: [ second.id ])
    expect([ two.amount_cents, two.fees_cents, order.reload.status ]).to eq([ 2_127, 127, "refunded" ])
    expect(order.refunded_cents).to eq(4_253)
    expect { described_class.issue!(order.reload) }.to raise_error(described_class::Error)
  end

  it "takes the tax back off the theater's tax report" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    order = sold(1)
    ticket = order.tickets.sole

    refund = described_class.issue!(order)
    expect(refund.tax_cents).to eq(205)
    lines = TaxLine.where(taxable: ticket).order(:id)
    expect(lines.pluck(:tax_cents)).to eq([ 205, -205 ])
    expect(lines.last.reversal_of_id).to eq(lines.first.id)
    expect(balance(:tax_to_remit)).to eq(0)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end

  it "absorbing the fees: the buyer gets the price, the theater gets our 50¢ back" do
    refund = described_class.issue!(sold(1, fee_mode: "org"))
    expect([ refund.amount_cents, refund.org_debit_cents ]).to eq([ 2_000, 1_950 ])
  end

  it "after the show, refuses a refund the balance can't cover" do
    order = sold(1)
    listing.update!(released_at: Time.current)
    allow(TicketBalance).to receive(:available_cents).and_return(1_000)

    expect { described_class.issue!(order) }.to raise_error(described_class::Error, /not enough to refund \$20.92/)
    expect(Stripe::Refund).not_to have_received(:create)
    expect([ order.reload.status, order.ticket_refunds.count ]).to eq([ "paid", 0 ])
  end

  it "puts everything back when Stripe refuses" do
    allow(Stripe::Refund).to receive(:create).and_raise(Stripe::StripeError.new("charge disputed"))
    order = sold(1)

    expect { described_class.issue!(order) }.to raise_error(described_class::Error, /charge disputed/)
    expect(order.reload.status).to eq("paid")
    expect(order.ticket_refunds.sole.status).to eq("failed")
    expect(OrgCashEntry.balance_cents(org)).to eq(2_000)
    expect(order.tickets.pluck(:status)).to eq([ "valid" ])
  end

  it "after the show, refunds only when the theater allows them" do
    order = sold(1)
    second = sold(1, intent: "pi_second")
    listing.show.update!(date_and_time: 2.hours.ago)

    expect(described_class.allowed?(order)).to be(false)
    expect { described_class.issue!(order) }.to raise_error(described_class::Error, /Refunds after the show are off/)
    expect(Stripe::Refund).not_to have_received(:create)

    # Canceling a show (started before showtime) isn't stopped by the setting.
    expect(described_class.issue!(order, allow_after_show: true).status).to eq("succeeded")

    TicketingProfile.for(org).update!(refunds_after_show: true)
    expect(described_class.issue!(second).status).to eq("succeeded")
  end

  it "hands cash back from the box, with no Stripe and no balance" do
    order = TicketDoor.new(listing, create(:user)).sell({ general.id.to_s => "1" }, kind: "cash")
    refund = described_class.issue!(order)

    expect(Stripe::Refund).not_to have_received(:create)
    expect([ refund.amount_cents, OrgCashEntry.balance_cents(org) ]).to eq([ 2_000, 0 ])
    expect(balance(:door_cash)).to eq(0)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end
end

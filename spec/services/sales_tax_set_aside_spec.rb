# frozen_string_literal: true

require "rails_helper"

# Sales tax kept out of what payout runs and withdrawals can spend, on by
# default (Tim, 2026-10-12): once a show's money is spendable its tax stays
# apart, until the organization marks the period paid.
RSpec.describe SalesTaxSetAside do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:listing) do
    create(:ticket_listing, organization: org,
                            show: create(:show, production: create(:production, organization: org), date_and_time: Time.zone.local(2026, 10, 10, 19, 30)))
  end
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    TicketTaxSetting.save!(org, name: "Amusement tax", percent: "9", mode: "added")
    org.update_column(:sales_tax_set_aside_since, Date.new(2026, 10, 1))
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
  end

  # Five $20 tickets with $1.80 tax each, sold Oct 1 for the Oct 10 show.
  def sell(count = 5)
    travel_to(Time.zone.local(2026, 10, 1, 12)) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
      order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_sale")
      order.reload
    end
  end

  def after_the_show(&)
    travel_to(Time.zone.local(2026, 10, 13, 12)) do
      TicketMoneyReleaseJob.perform_now
      yield
    end
  end

  it "keeps the tax out of the balance's spendable money once the show has settled" do
    sell

    travel_to(Time.zone.local(2026, 10, 5, 12)) do
      # Before the show the whole sale is held for it; nothing is held twice.
      expect(described_class.cents(org)).to eq(0)
      expect(CocoScoutBalance.summary(org).upcoming_cents).to eq(10_900)
    end

    after_the_show do
      summary = CocoScoutBalance.summary(org)
      expect(summary.tax_set_aside_cents).to eq(900)
      expect(summary.available_cents).to eq(10_000)
      expect(summary.total_cents).to eq(10_900)
      expect(OrgCashEntry.available_cents(org)).to eq(10_000)
      expect(described_class.by_month(org)).to eq([ [ Date.new(2026, 10, 1), 900 ] ])
    end
  end

  it "lets the money go once the period is marked paid, and takes it back on undo" do
    sell

    after_the_show do
      paid = org.sales_tax_remittances.create!(tax_name: "Amusement tax", rate_bps: 900, basis: "sale",
                                               period_start: Date.new(2026, 10, 1), period_end: Date.new(2026, 10, 31),
                                               amount_cents: 900, paid_on: Date.current)
      expect(described_class.cents(org)).to eq(0)
      expect(CocoScoutBalance.available_cents(org)).to eq(10_900)
      expect(ChartOfAccounts.account(org, :tax_to_remit).natural_balance_cents).to eq(0)
      expect(BooksReconciliation.check(org).map(&:account)).not_to include("tax_to_remit")
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

      # A period paid by show date covers it too; one for another tax doesn't.
      paid.destroy!
      expect(described_class.cents(org)).to eq(900)
      expect(ChartOfAccounts.account(org, :tax_to_remit).natural_balance_cents).to eq(900)
      org.sales_tax_remittances.create!(tax_name: "Sales tax", rate_bps: 900, basis: "sale", period_start: Date.new(2026, 10, 1),
                                        period_end: Date.new(2026, 10, 31), amount_cents: 0, paid_on: Date.current)
      expect(described_class.cents(org)).to eq(900)
      org.sales_tax_remittances.create!(tax_name: "Amusement tax", rate_bps: 900, basis: "event", period_start: Date.new(2026, 10, 1),
                                        period_end: Date.new(2026, 10, 31), amount_cents: 900, paid_on: Date.current)
      expect(described_class.cents(org)).to eq(0)
    end
  end

  it "lets a refund after the show spend the tax it gives back" do
    order = sell
    ticket = order.tickets.first

    after_the_show do
      debit = TicketOrderRefund.quote(order, ticket_ids: [ ticket.id ]).org_debit_cents
      expect(described_class.relief_cents(org, ticket_ids: [ ticket.id ])).to eq(180)
      # Leave the spendable balance just short of the refund without its tax.
      OrgCashEntry.post!(organization: org, entry_type: "adjustment", amount_cents: -(10_000 - (debit - 100)), description: "Spent elsewhere")
      expect(CocoScoutBalance.available_cents(org)).to eq(debit - 100)

      TicketOrderRefund.issue!(order, ticket_ids: [ ticket.id ], outside_policy: true)

      expect(described_class.cents(org)).to eq(720)
      expect(CocoScoutBalance.raw_available_cents(org)).to be >= 0
    end
  end

  it "sets nothing aside from before it started, when it's off, or for cash at the door" do
    order = sell

    after_the_show do
      org.update_column(:sales_tax_set_aside_since, Date.new(2026, 10, 2))
      expect(described_class.cents(org)).to eq(0)

      org.update_column(:sales_tax_set_aside_since, nil)
      expect(described_class.cents(org)).to eq(0)
      expect(CocoScoutBalance.available_cents(org)).to eq(10_900)

      org.update_column(:sales_tax_set_aside_since, Date.new(2026, 10, 1))
      order.update_column(:money_path, "cash")
      expect(described_class.cents(org)).to eq(0)
    end
  end
end

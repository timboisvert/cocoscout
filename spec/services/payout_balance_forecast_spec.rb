# frozen_string_literal: true

require "rails_helper"

# "If you wait": what the bank would pay for a waiting run on each day the
# money already sold changes it (Tim, 2026-11-22).
RSpec.describe PayoutBalanceForecast do
  let(:org) do
    create(:organization, :pro, stripe_account_id: "acct_theater", payouts_enabled: true, time_zone: "Central Time (US & Canada)",
                                stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account")
  end
  let(:now) { Time.zone.parse("2026-11-22 09:00 CST") }
  let(:show_at) { Time.zone.parse("2026-11-24 19:30 CST") }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: show_at)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  def sell(count, at:)
    travel_to(at) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
      TicketOrderSettlement.settle!(order)
      order.reload
    end
  end

  def waiting_run(*amounts)
    batch = org.payout_batches.create!(kind: "payout", status: "funding", funding_status: "awaiting_balance", trigger: "manual",
                                       bank_due_at: now + 3.days)
    amounts.each do |cents|
      payee = create(:person, stripe_account_id: "acct_#{SecureRandom.hex(3)}", payouts_enabled: true)
      item = batch.items.create!(payee: payee, amount_cents: cents, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee, amount_cents: cents, label: "Pay")
    end
    batch.recalculate_total!
    batch
  end

  it "counts contract money two days after it came in" do
    OrgCashEntry.post!(organization: org, entry_type: "contract_payment", amount_cents: 3_000, source: nil,
                       description: "Contract payment", occurred_at: now - 1.day)
    batch = waiting_run(2_000, 2_000)

    rows = travel_to(now) { described_class.rows(batch, now: now) }
    # Nothing more is on its way: no day after the scheduled debit would change it.
    expect(rows.map { |r| [ r.date.to_s, r.bank_cents, r.covered ] })
      .to eq([ [ "2026-11-22", 4_000, 0 ], [ "2026-11-23", 1_000, 1 ], [ "2026-11-25", 1_000, 1 ] ])
  end

  it "waits on the show, and on two days after each sale, for ticket money" do
    order = sell(5, at: now - 1.day) # sold Saturday for Tuesday's show
    batch = waiting_run(order.org_net_cents)

    rows = travel_to(now) { described_class.rows(batch, now: now) }
    # Settled Monday, but the show is Tuesday night: released Wednesday at 4am.
    expect(rows.map { |r| [ r.date.to_s, r.bank_cents ] })
      .to eq([ [ "2026-11-22", order.org_net_cents ], [ "2026-11-25", 0 ] ])
  end

  describe ".advice" do
    row = ->(date, bank) { described_class::Row.new(date: Date.parse(date), available_cents: 0, covered: 0, bank_cents: bank) }
    bank_day = Date.parse("2026-11-25")

    it "says when money already sold covers everyone before the scheduled bank debit" do
      advice = described_class.advice([ row.call("2026-11-22", 4_000), row.call("2026-11-24", 0), row.call("2026-11-25", 0) ], bank_day: bank_day)
      expect(advice).to eq(text: "Ticket money already sold should cover everyone left by Tuesday, November 24, so your bank shouldn't have to pay anything.", wait_until: nil)
    end

    it "offers a later debit day when that saves the whole debit" do
      advice = described_class.advice([ row.call("2026-11-22", 4_000), row.call("2026-11-25", 1_900), row.call("2026-11-26", 0) ], bank_day: bank_day)
      expect(advice).to eq(text: "If you wait until Thursday, November 26, your bank shouldn't have to pay anything.",
                           wait_until: Date.parse("2026-11-26"))
    end

    it "says what waiting for the scheduled debit saves, or that it saves nothing" do
      expect(described_class.advice([ row.call("2026-11-22", 4_000), row.call("2026-11-25", 1_900) ], bank_day: bank_day)[:text])
        .to eq("The bank debit is scheduled for Wednesday, November 25. By then it should be $19.00 instead of $40.00.")
      expect(described_class.advice([ row.call("2026-11-22", 4_000), row.call("2026-11-25", 4_000) ], bank_day: bank_day)[:text])
        .to eq("No more ticket money clears before the bank debit on Wednesday, November 25, so waiting won't make it smaller.")
    end
  end

  it "leaves out money for a canceled show, which refunds its buyers" do
    sell(5, at: now - 1.day)
    listing.show.update!(canceled: true)
    expect(travel_to(now) { described_class.incoming(org, now: now) }).to be_empty
  end
end

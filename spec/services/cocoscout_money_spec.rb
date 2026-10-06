# frozen_string_literal: true

require "rails_helper"

# CocoScout's own money beside the theaters', both checked against Stripe:
# the balance lines Stripe reports are matched to the records that caused
# them, CocoScout's share of each payment lands in its own ledger, and the
# daily check finds Stripe's balance = held for theaters + CocoScout's own.
RSpec.describe "CocoScout's money" do
  let(:org) { create(:organization, :pro, stripe_account_id: "acct_theater", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.weeks.from_now)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  def line(id, type:, category:, amount:, fee: 0, source: nil)
    Stripe::BalanceTransaction.construct_from(
      id: id, object: "balance_transaction", type: type, reporting_category: category, amount: amount, fee: fee,
      net: amount - fee, currency: "usd", status: "available", created: Time.current.to_i, available_on: Time.current.to_i,
      description: nil, source: source
    )
  end

  def stripe_balance(cents)
    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(available: [ { amount: cents, currency: "usd" } ], pending: [ { amount: 0, currency: "usd" } ])
    )
  end

  def ours(type)
    CocoScoutLedgerEntry.where(entry_type: type).sum(:amount_cents)
  end

  def sell_two_tickets
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    TicketOrderSettlement.settle!(order)
    order.reload.update!(stripe_payment_intent_id: "pi_tickets", stripe_fee_cents: 152)
    order
  end

  it "takes CocoScout's share of a ticket sale from what the theater wasn't credited" do
    order = sell_two_tickets
    credit = OrgCashEntry.find_by(source: order, entry_type: "ticket_sale").amount_cents

    expect(ours("ticket_fee")).to eq(100)
    expect(ours("ticket_processing")).to eq(order.total_cents - credit - 100)
    expect(ours("processing_cost")).to eq(-152)
  end

  it "accounts for every cent in Stripe, and lists what it can't" do
    order = sell_two_tickets
    registration = create(:course_offering, production: create(:production, organization: org, production_type: "course"), price_cents: 10_000)
                   .course_registrations.create!(person: create(:person), status: :confirmed, amount_cents: 10_000, tax_cents: 0, currency: "usd",
                                                 registered_at: Time.current, paid_at: Time.current, stripe_payment_intent_id: "pi_course",
                                                 cocoscout_fee_cents: 1_000, stripe_fee_cents: 320)
    batch = org.payout_batches.create!(kind: "payout", status: "funded", trigger: "manual", funding_status: "succeeded",
                                       funding_payment_intent_id: "pi_fund", total_cents: 200_000)
    OrgCashEntry.post!(organization: org, entry_type: "funding", amount_cents: 200_000, source: batch, description: "Funding")
    payee = create(:person, stripe_account_id: "acct_payee", payouts_enabled: true)
    item = batch.items.create!(payee: payee, amount_cents: 5_000, status: "pending")
    item.mark_paid!(transfer_id: "tr_payee")
    OrgCashEntry.post!(organization: org, entry_type: "transfer", amount_cents: -5_000, source: item, description: "Paid")
    withdrawal = org.balance_withdrawals.create!(amount_cents: 1_000, status: "sent", stripe_transfer_id: "tr_withdraw")
    OrgCashEntry.post!(organization: org, entry_type: "transfer", amount_cents: -1_000, source: withdrawal, description: "Withdrawal")
    org.update!(stripe_customer_id: "cus_org")
    BillingInvoice.create!(organization: org, stripe_invoice_id: "in_pro", kind: "pro", status: "paid", amount_due_cents: 2_000, amount_paid_cents: 2_000,
                           stripe_payment_intent_id: "pi_pro", paid_at: Time.current)

    lines = [
      line("txn_1", type: "charge", category: "charge", amount: order.total_cents, fee: 152, source: { id: "ch_1", object: "charge", payment_intent: "pi_tickets" }),
      line("txn_2", type: "charge", category: "charge", amount: 10_000, fee: 320, source: { id: "ch_2", object: "charge", payment_intent: "pi_course" }),
      line("txn_3", type: "payment", category: "charge", amount: 200_000, fee: 500, source: { id: "py_3", object: "charge", payment_intent: "pi_fund" }),
      line("txn_4", type: "transfer", category: "transfer", amount: -5_000, source: { id: "tr_payee", object: "transfer" }),
      line("txn_5", type: "transfer", category: "transfer", amount: -1_000, source: { id: "tr_withdraw", object: "transfer" }),
      line("txn_6", type: "charge", category: "charge", amount: 2_000, fee: 88, source: { id: "ch_6", object: "charge", customer: "cus_org", payment_intent: "pi_pro" }),
      line("txn_7", type: "stripe_fee", category: "fee", amount: -200, source: nil),
      line("txn_8", type: "payout", category: "payout", amount: -10_000, source: { id: "po_1", object: "payout" })
    ]
    lines.each { |l| StripeBalanceTransaction.import!(l) }
    stripe_balance(lines.sum(&:net))

    expect(StripeBalanceTransaction.pluck(:stripe_id, :category, :match_status).to_h { |id, c, s| [ id, [ c, s ] ] }).to eq(
      "txn_1" => %w[ticket_order matched], "txn_2" => %w[course_registration matched], "txn_3" => %w[run_funding matched],
      "txn_4" => %w[payee_transfer matched], "txn_5" => %w[withdrawal matched], "txn_6" => %w[billing matched],
      "txn_7" => %w[stripe_fee matched], "txn_8" => %w[payout_to_bank matched]
    )
    expect(StripeBalanceTransaction.find_by(stripe_id: "txn_2").organization).to eq(org)
    expect(ours("course_fee")).to eq(1_000)
    expect(ours("subscription")).to eq(2_000)
    expect(ours("funding_cost")).to eq(-500)
    expect(ours("payout_to_bank")).to eq(-10_000)

    row = PlatformReconciliationCheck.run!
    expect(row.details["import_complete"]).to be(true)
    expect(row.difference_cents).to eq(0)
    expect([ row.unmatched_count, row.mismatch_count ]).to eq([ 0, 0 ])
    expect(row).to be_clean
    expect(registration).to be_present

    # Something Stripe did that CocoScout knows nothing about.
    mystery = line("txn_9", type: "adjustment", category: "other_adjustment", amount: 500)
    StripeBalanceTransaction.import!(mystery)
    stripe_balance(lines.sum(&:net) + 500)
    row = PlatformReconciliationCheck.run!
    expect([ row.difference_cents, row.unmatched_count ]).to eq([ 500, 1 ])
    expect(row).not_to be_clean

    StripeBalanceTransaction.find_by(stripe_id: "txn_9").explain!(note: "Stripe goodwill credit", by: create(:user))
    row = PlatformReconciliationCheck.run!
    expect([ row.difference_cents, row.unmatched_count ]).to eq([ 0, 0 ])
    expect(ours("explained")).to eq(500)
  end

  it "flags a Stripe line whose amount disagrees with its record" do
    order = sell_two_tickets
    StripeBalanceTransaction.import!(line("txn_x", type: "charge", category: "charge", amount: order.total_cents + 1, fee: 152,
                                          source: { id: "ch_x", object: "charge", payment_intent: "pi_tickets" }))
    expect(StripeBalanceTransaction.find_by(stripe_id: "txn_x").match_status).to eq("mismatch")
  end

  it "counts a bank debit Stripe shows before it lands as on its way in, and drops one that bounced" do
    org.update!(stripe_customer_id: "cus_sg", funding_payment_method_id: "pm_bank", funding_payment_method_type: "us_bank_account")
    batch = org.payout_batches.create!(kind: "payout", status: "funding", trigger: "manual", funding_status: "processing",
                                       funding_payment_intent_id: "pi_run", total_cents: 205_873)
    funding = line("txn_run", type: "payment", category: "charge", amount: 205_873, fee: 500, source: { id: "py_run", object: "charge", payment_intent: "pi_run" })
    StripeBalanceTransaction.import!(funding)
    stripe_balance(funding.net)

    row = PlatformReconciliationCheck.run!
    expect([ row.difference_cents, row.details["in_transit_cents"] ]).to eq([ 0, 205_873 ])
    expect(row.details["in_transit"].sole).to include("label" => "Payout run ##{batch.id}: bank debit on its way")
    expect(row).to be_clean

    # It lands: the theater is credited and nothing is on its way any more.
    allow(PayoutBatchService).to receive(:process!)
    PayoutBatchService.advance_funding!(batch, "succeeded", funded_cents: 205_873)
    row = PlatformReconciliationCheck.run!
    expect([ row.difference_cents, row.details["in_transit_cents"] ]).to eq([ 0, 0 ])

    # Another run whose debit bounced: Stripe's failure line cancels its charge.
    bounced = org.payout_batches.create!(kind: "payout", status: "failed", trigger: "manual", funding_status: "failed",
                                         funding_payment_intent_id: "pi_bounce", total_cents: 10_000)
    StripeBalanceTransaction.import!(line("txn_b1", type: "payment", category: "charge", amount: 10_000, fee: 80, source: { id: "py_b", object: "charge", payment_intent: "pi_bounce" }))
    StripeBalanceTransaction.import!(line("txn_b2", type: "payment_failure_refund", category: "charge_failure", amount: -10_000, source: { id: "py_b", object: "charge", payment_intent: "pi_bounce" }))
    expect(StripeBalanceTransaction.where(matched: bounced).pluck(:match_status)).to eq(%w[matched matched])
    stripe_balance(funding.net - 80)
    expect(PlatformReconciliationCheck.run!.difference_cents).to eq(0)
  end

  it "takes the Stripe money a theater's balance gave up when CocoScout paid it by hand" do
    payout = OrgPayout.create!(organization: org, amount_cents: 45_000, payment_method: "check", payout_type: "custom",
                               status: "paid", paid_at: Time.current, paid_by_user: create(:user))
    expect(OrgCashEntry.find_by(source: payout).amount_cents).to eq(-45_000)
    expect(ours("paid_by_hand")).to eq(45_000)

    payout.destroy!
    expect(OrgCashEntry.where(source_type: "OrgPayout")).to be_empty
    expect(ours("paid_by_hand")).to eq(0)
  end

  it "counts only the difference when a mismatched line is explained" do
    order = sell_two_tickets
    StripeBalanceTransaction.import!(line("txn_m", type: "charge", category: "charge", amount: order.total_cents + 500, fee: 152,
                                          source: { id: "ch_m", object: "charge", payment_intent: "pi_tickets" }))
    StripeBalanceTransaction.find_by(stripe_id: "txn_m").explain!(note: "Price changed after the sale", by: create(:user))
    expect(ours("explained")).to eq(500)
  end

  it "takes back a bill's income when CocoScout refunds it" do
    bill = BillingInvoice.create!(organization: org, stripe_invoice_id: "in_jul", kind: "usage", status: "paid", amount_due_cents: 28_000,
                                  amount_paid_cents: 28_000, stripe_payment_intent_id: "pi_jul", paid_at: 2.months.ago)
    StripeBalanceTransaction.import!(line("txn_bill", type: "payment", category: "charge", amount: 28_000, fee: 224,
                                          source: { id: "py_jul", object: "charge", payment_intent: "pi_jul" }))
    StripeBalanceTransaction.import!(line("txn_refund", type: "refund", category: "refund", amount: -28_000,
                                          source: { id: "re_jul", object: "refund", charge: "py_jul", payment_intent: "pi_jul" }))

    refund = StripeBalanceTransaction.find_by(stripe_id: "txn_refund")
    expect([ refund.category, refund.match_status, refund.matched, refund.organization ]).to eq([ "billing_refund", "matched", bill, org ])
    expect(ours("usage")).to eq(0)
    expect(CocoScoutLedgerEntry.where(organization: org, entry_type: "usage").sum(:amount_cents)).to eq(0)
    stripe_balance(28_000 - 224 - 28_000)
    expect(PlatformReconciliationCheck.run!.difference_cents).to eq(0)
  end

  it "gives back the fees a ticket refund returned to the buyer" do
    order = sell_two_tickets
    refund = TicketRefund.create!(organization: org, ticket_order: order, status: "succeeded", amount_cents: order.total_cents,
                                  org_debit_cents: order.org_net_cents, platform_fee_waived_cents: 100, stripe_refund_id: "re_1")
    OrgCashEntry.post!(organization: org, entry_type: "ticket_refund", amount_cents: -order.org_net_cents, source: refund, description: "Refund")
    expect(ours("ticket_refund")).to eq(-(order.total_cents - order.org_net_cents))
  end

  describe "the morning email" do
    before { stripe_balance(0) }

    it "waits a day before raising a difference, and goes to both superadmins" do
      CocoScoutLedgerEntry.post!(source: org, entry_type: "explained", amount_cents: 100, occurred_at: Time.current)
      travel_to(Time.zone.local(2026, 10, 6, 6)) do
        expect { PlatformReconciliationJob.perform_now }.not_to have_enqueued_mail(AppMailer, :send_template)
      end
      travel_to(Time.zone.local(2026, 10, 7, 6)) do
        expect { PlatformReconciliationJob.perform_now }.to have_enqueued_mail(AppMailer, :send_template).twice
      end
    end
  end

  before { allow(Stripe::BalanceTransaction).to receive(:list).and_return(double(auto_paging_each: nil)) }
end

RSpec.describe BillingInvoiceSync do
  let(:org) { create(:organization, :pro, stripe_customer_id: "cus_org", stripe_subscription_id: "sub_pro", staffing_subscription_id: "sub_usage") }

  before { org }

  it "reads a bill in the newer API's shape" do
    invoice = Stripe::Invoice.construct_from(
      id: "in_1", object: "invoice", customer: "cus_org", number: "SG-0002", status: "paid",
      amount_due: 3_500, amount_paid: 3_500, amount_remaining: 0, period_start: 1.month.ago.to_i, period_end: Time.current.to_i,
      parent: { subscription_details: { subscription: "sub_usage" } },
      payments: { data: [ { payment: { payment_intent: "pi_usage" } } ] },
      lines: { data: [ { description: "7 × active staff member", quantity: 7, amount: 3_500, pricing: { price_details: { price: "price_unknown" } } } ] },
      status_transitions: { finalized_at: 1.day.ago.to_i, paid_at: Time.current.to_i }
    )
    record = described_class.sync!(invoice)
    expect(record.attributes.slice("kind", "status", "amount_paid_cents", "stripe_payment_intent_id", "stripe_subscription_id"))
      .to eq("kind" => "usage", "status" => "paid", "amount_paid_cents" => 3_500, "stripe_payment_intent_id" => "pi_usage", "stripe_subscription_id" => "sub_usage")
    expect(record.lines.first).to include("quantity" => 7, "amount_cents" => 3_500)
    expect(CocoScoutLedgerEntry.find_by(source: record).attributes.slice("entry_type", "amount_cents")).to eq("entry_type" => "usage", "amount_cents" => 3_500)
  end

  it "reads a bill in the older shape" do
    invoice = Stripe::Invoice.construct_from(id: "in_2", object: "invoice", customer: "cus_org", status: "open", subscription: "sub_pro",
                                             payment_intent: "pi_pro", amount_due: 2_000, amount_paid: 0, amount_remaining: 2_000, lines: { data: [] })
    record = described_class.sync!(invoice)
    expect(record.attributes.slice("kind", "status", "stripe_payment_intent_id")).to eq("kind" => "pro", "status" => "open", "stripe_payment_intent_id" => "pi_pro")
    expect(CocoScoutLedgerEntry.where(source: record)).to be_empty
  end
end

RSpec.describe "Monthly statements" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, email_address: "owner@starsandgarters.com") }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: Time.zone.local(2026, 9, 20, 19, 30))) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  it "says what the theater paid CocoScout and what happened to its balance, and emails it once" do
    travel_to(Time.zone.local(2026, 9, 10, 12)) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "4" })
      TicketOrderSettlement.settle!(order)
      order.reload.update!(stripe_payment_intent_id: "pi_s", stripe_fee_cents: 260)
    end
    BillingInvoice.create!(organization: org, stripe_invoice_id: "in_u", kind: "usage", status: "paid", amount_due_cents: 3_500, amount_paid_cents: 3_500,
                           period_start: Time.zone.local(2026, 8, 1), paid_at: Time.zone.local(2026, 9, 1, 9), number: "SG-0002")

    totals = OrgStatementBuilder.totals(org, Date.new(2026, 9, 1))
    expect(totals["paid"].to_h).to include("Ticket fees (50¢ a ticket)" => 200, "Usage" => 3_500)
    expect(totals["paid_tickets"]).to eq(4)
    expect(totals["opening_cents"]).to eq(0)
    expect(totals["closing_cents"]).to eq(OrgCashEntry.balance_cents(org))
    expect(totals["bills"].sole).to include("label" => "Usage", "status" => "Paid", "amount_cents" => 3_500)

    travel_to(Time.zone.local(2026, 10, 1, 8)) do
      expect { perform_enqueued_jobs { MonthlyStatementsJob.perform_now } }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end
    statement = org.org_statements.sole
    expect(statement.pdf).to be_attached
    expect(statement.emailed_at).to be_present
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "owner@starsandgarters.com" ])
    expect(mail.subject).to eq("Your CocoScout statement for September 2026")
    expect(mail.attachments.map(&:filename)).to include(a_string_ending_with("2026-09.pdf"))

    expect { perform_enqueued_jobs { OrgStatementJob.perform_now(org.id, "2026-09-01") } }.not_to(change { ActionMailer::Base.deliveries.size })
  end
end

RSpec.describe UsageRules do
  let(:org) { create(:organization, :pro) }
  let(:paid_role) { create(:house_role, organization: org, name: "Bartender", pay_type: "hourly", default_hourly_rate_cents: 2_000) }
  let(:unpaid_role) { create(:house_role, organization: org, name: "Greeter", pay_type: "hourly", default_hourly_rate_cents: nil) }
  let(:ruby) { create(:person, name: "Ruby Infante") }
  let(:colin) { create(:person, name: "Colin Kelty") }
  let(:phoebe) { create(:person, name: "Phoebe Davis") }

  def staff!(person, rate_cents: nil)
    create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: rate_cents)
  end

  def shift!(role, person, at)
    shift = Shift.create!(organization: org, house_role: role, starts_at: at, ends_at: at + 4.hours)
    shift.shift_assignments.create!(person: person)
    shift
  end

  # Tim, 2026-10-05: charged for each month someone works a shift, once it's
  # over, in a role that pays them; to the month of the work, not the payout.
  it "counts a staff member for the month of a paid shift that's over, and nobody else" do
    staff!(ruby, rate_cents: 2_000)
    staff!(colin)
    staff!(phoebe, rate_cents: 2_000)
    shift!(paid_role, ruby, Time.zone.local(2026, 9, 27, 18))      # worked in September
    shift!(unpaid_role, colin, Time.zone.local(2026, 10, 2, 18))   # a role that pays nothing
    shift!(paid_role, phoebe, Time.zone.local(2026, 10, 20, 18))   # scheduled, not worked yet

    now = Time.zone.local(2026, 10, 5, 12)
    expect(described_class.staff(Date.new(2026, 9, 1), now: now).transform_values(&:keys)).to eq(org.id => [ ruby.id ])
    expect(described_class.staff(Date.new(2026, 10, 1), now: now)).to eq({})
    expect(described_class.staff(Date.new(2026, 10, 1), now: Time.zone.local(2026, 10, 21)).transform_values(&:keys)).to eq(org.id => [ phoebe.id ])
  end

  it "counts a flat-paid role, and not a declined shift" do
    flat = create(:house_role, organization: org, name: "Door", pay_type: "flat", default_flat_rate_cents: 5_000)
    staff!(ruby)
    staff!(colin, rate_cents: 2_000)
    shift!(flat, ruby, Time.zone.local(2026, 9, 10, 18))
    shift!(paid_role, colin, Time.zone.local(2026, 9, 11, 18)).shift_assignments.first.update!(declined_at: Time.zone.local(2026, 9, 1))
    expect(described_class.staff(Date.new(2026, 9, 1), now: Time.zone.local(2026, 10, 1)).transform_values(&:keys)).to eq(org.id => [ ruby.id ])
  end

  it "rebuilds a month counted under the old rule, and the sweep only adds" do
    staff!(ruby, rate_cents: 2_000)
    shift!(paid_role, ruby, Time.zone.local(2026, 9, 27, 18))
    StaffActivation.record!(organization: org, person: colin, month: Date.new(2026, 9, 1))

    change = UsageRebuild.run!(Date.new(2026, 9, 1), now: Time.zone.local(2026, 10, 5)).sole
    expect([ change.kind, change.added, change.removed ]).to eq([ "staff", [ "Ruby Infante" ], [ "Colin Kelty" ] ])
    expect(StaffActivation.for_month(Date.new(2026, 9, 1)).pluck(:person_id)).to eq([ colin.id ])

    travel_to(Time.zone.local(2026, 10, 5, 12)) { UsageSweepJob.perform_now }
    expect(StaffActivation.for_month(Date.new(2026, 9, 1)).pluck(:person_id)).to contain_exactly(colin.id, ruby.id)

    UsageRebuild.run!(Date.new(2026, 9, 1), post: true, now: Time.zone.local(2026, 10, 5))
    expect(StaffActivation.for_month(Date.new(2026, 9, 1)).pluck(:person_id)).to eq([ ruby.id ])
  end
end

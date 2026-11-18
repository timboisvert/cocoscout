# frozen_string_literal: true

require "rails_helper"

# Payouts paid by hand before the payout ledger existed (Tim, 2026-11-10:
# "Yes, fix first"). Financials counted them and Books didn't: at Stars &
# Garters, $22,832 across 528 lines. They go on the ledger as an earning and
# a payout that cancel, so the books show the pay and nobody's balance moves.
RSpec.describe HandPaidPayouts do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Starlets") }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 3, 14, 20, 0)) }
  let(:payout) { create(:show_payout, show: show) }
  let(:ana) { create(:person, name: "Ana Diaz") }
  let(:ben) { create(:person, name: "Ben Lee") }
  let(:paid_on) { Time.zone.local(2026, 3, 16, 9, 0) }

  # A line settled the old way: marked paid, with nothing on the ledger.
  def hand_paid(payee, amount, on: payout, **attrs)
    create(:show_payout_line_item, show_payout: on, payee: payee, amount: amount, manually_paid: true,
                                   manually_paid_at: paid_on, paid_at: paid_on, payment_method: "zelle", **attrs)
  end

  def balance(key) = ChartOfAccounts.account(org, key).natural_balance_cents

  it "puts each one on the ledger as an earning and a payout that cancel, dated the show and the day it was paid" do
    line = hand_paid(ana, 52.38)
    hand_paid(ben, 64)
    expect(described_class.missing(org).count).to eq(2)

    result = described_class.post!(org)
    expect(result).to have_attributes(lines: 2, cents: 11_638, people: 2, zero: 0, guests: 0, contract_lines: 0)

    earning, paid = PayoutLedgerEntry.where(source: line).order(:entry_type).to_a
    expect([ earning.entry_type, earning.amount_cents, earning.occurred_at.to_date ]).to eq([ "earning", 5_238, Date.new(2026, 3, 14) ])
    expect([ paid.entry_type, paid.amount_cents, paid.occurred_at.to_date, paid.description ]).to eq([ "payout", -5_238, Date.new(2026, 3, 16), "Paid via Zelle" ])
    expect(org.payout_balance_cents_for(ana)).to eq(0)
    expect(org.payout_balance_cents_for(ben)).to eq(0)

    # On the books: the pay as an expense of the show, out of the bank, nothing left owed.
    expect(balance(:performer_pay)).to eq(11_638)
    expect(balance(:bank)).to eq(-11_638)
    expect(balance(:owed_to_payees)).to eq(0)
    expect(JournalLine.where(organization: org, ledger_account: ChartOfAccounts.account(org, :performer_pay)).pluck(:show_id, :production_id).uniq)
      .to eq([ [ show.id, production.id ] ])
    expect(BooksReconciliation.check(org)).to be_empty

    # A second pass finds nothing left.
    expect(described_class.missing(org)).to be_empty
    expect(described_class.post!(org).lines).to eq(0)
    expect(balance(:performer_pay)).to eq(11_638)
  end

  it "leaves what someone is already owed exactly as it was" do
    # Ben is owed $40 for a newer show, on the ledger the usual way.
    newer = create(:show_payout, show: create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 2, 20, 0)))
    create(:show_payout_line_item, show_payout: newer, payee: ben, amount: 40).sync_earning_ledger_entry!
    hand_paid(ben, 64)
    expect { described_class.post!(org) }.not_to(change { org.payout_balance_cents_for(ben) })
    expect(org.payout_balance_cents_for(ben)).to eq(4_000)
  end

  it "leaves alone a line the ledger already knows, a $0 line, a guest, and a contract show's line" do
    known = hand_paid(ana, 30)
    known.sync_earning_ledger_entry!
    known.sync_payout_ledger_entry!
    hand_paid(ben, 0, payment_method: "n/a")
    hand_paid(nil, 75, is_guest: true, guest_name: "Aura Star")
    # A contract show: what the contractor got is the contract's own payment.
    rented = create(:production, organization: org, name: "A Random Memory", production_type: "third_party")
    contractor = create(:contractor, organization: org)
    hand_paid(contractor, 138.5, on: create(:show_payout, show: create(:show, production: rented)))

    ledger = PayoutLedgerEntry.where(organization: org).count
    result = described_class.post!(org)
    expect(result).to have_attributes(lines: 0, cents: 0, zero: 1, guests: 1, guest_cents: 7_500, contract_lines: 1, contract_cents: 13_850)
    expect(PayoutLedgerEntry.where(organization: org).count).to eq(ledger)
  end

  it "refuses, keeping nothing, if anyone's balance would move" do
    hand_paid(ana, 50)
    # A payout that never lands would leave Ana owed $50 she was already paid.
    allow_any_instance_of(ShowPayoutLineItem).to receive(:sync_payout_ledger_entry!)
    result = BooksBackfill.run!(dry_run: false, organization_ids: [ org.id ])
    expect(result.rows).to be_empty
    expect(result.failures.sole.error).to include("HandPaidPayouts::BalanceMoved", "1 balance(s) would change")
    expect(PayoutLedgerEntry.where(organization: org)).to be_empty
  end

  it "runs as part of the books backfill, which reports it and keeps nothing on a dry run" do
    hand_paid(ana, 52.38)
    dry = BooksBackfill.run!(dry_run: true, organization_ids: [ org.id ]).rows.sole
    expect(dry.hand_paid).to have_attributes(lines: 1, cents: 5_238, people: 1)
    expect(dry.mismatches).to be_empty
    expect(PayoutLedgerEntry.where(organization: org)).to be_empty

    row = BooksBackfill.run!(dry_run: false, organization_ids: [ org.id ]).rows.sole
    expect(row.hand_paid.lines).to eq(1)
    expect(row.trial_balance_cents).to eq(0)
    expect(balance(:performer_pay)).to eq(5_238)
  end
end

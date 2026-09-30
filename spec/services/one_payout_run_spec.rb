# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260930160000_label_open_runs_as_payouts")

# One payout run for everything: staff pay rides the same open run as show
# payouts, course money and contract payments. A person paid for both gets one
# transfer, but the two kinds of money settle and post separately — staff pay
# exactly as entered, performer money netted against advances.
RSpec.describe "One payout run" do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:person) { create(:person, name: "Dual Dana", stripe_account_id: "acct_dual", payouts_enabled: true) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }
  let(:production) { create(:production, organization: org) }

  def staff_pay!(hours:)
    StaffPayRunService.add_lines!(organization: org, created_by: owner,
                                  lines: [ { staff_member: member, hours: hours, bonus_cents: 0,
                                             reimbursement_cents: 0, tips_cents: 0 } ]).batch
  end

  def show_pay!(dollars)
    show = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)
    payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: dollars)
    line = ShowPayoutLineItem.create!(show_payout: payout, payee: person, amount: dollars)
    PerformerPayoutRunService.add_show_payout!(payout)
    line
  end

  def ledger(category)
    org.payout_balance_cents_for(person, category: category)
  end

  it "puts staff pay and show pay on the same run and the same item, whichever comes first" do
    batch = staff_pay!(hours: 5)            # $100 staff
    show_pay!(200)                          # $200 show

    expect(PayoutBatch.current_open_draft(org)).to eq(batch)
    item = batch.reload.items.sole
    expect(item.payee).to eq(person)
    expect(item.payout_contributions.pluck(:category).tally).to eq("staffing" => 1, "performer" => 1)
    expect(item.amount_cents).to eq(30_000)
    expect(batch.total_cents).to eq(30_000)
  end

  it "takes an outstanding advance out of performer money only, never staff pay" do
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "advance",
                            amount_cents: -5_000, category: "performer", description: "old advance")
    show_pay!(200)
    batch = staff_pay!(hours: 5)

    item = batch.reload.items.sole
    # $100 staff as entered + ($200 show − $50 advance)
    expect(item.amount_cents).to eq(25_000)
    expect(item.category_split).to eq("performer" => 15_000, "staffing" => 10_000)

    # An advance bigger than the show pay still leaves the staff pay whole.
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "advance",
                            amount_cents: -50_000, category: "performer", description: "big advance")
    item.settle_amount!
    expect(item.reload.amount_cents).to eq(10_000)
  end

  it "posts one payout per kind of money when paid, and unwinds both" do
    staff_pay!(hours: 5)
    show_pay!(200)
    batch = PayoutBatch.current_open_draft(org)
    item = batch.items.sole

    item.mark_paid!(transfer_id: "tr_1")
    payouts = PayoutLedgerEntry.where(source: item, entry_type: "payout")
    expect(payouts.pluck(:category, :amount_cents)).to contain_exactly([ "staffing", -10_000 ], [ "performer", -20_000 ])
    expect(ledger("staffing")).to eq(0)
    expect(ledger("performer")).to eq(0)

    item.mark_returned!(reason: "account closed")
    reversals = PayoutLedgerEntry.where(source: item, entry_type: "reversal")
    expect(reversals.pluck(:category, :amount_cents)).to contain_exactly([ "staffing", 10_000 ], [ "performer", 20_000 ])
  end

  it "removes both payout entries when a transfer fails" do
    staff_pay!(hours: 5)
    show_pay!(200)
    item = PayoutBatch.current_open_draft(org).items.sole
    item.mark_paid!(transfer_id: "tr_1")

    item.mark_failed!("declined")
    expect(PayoutLedgerEntry.where(source: item, entry_type: "payout")).to be_empty
    expect(ledger("staffing")).to eq(10_000)
    expect(ledger("performer")).to eq(20_000)
  end

  it "discards a mixed run: staff pay back to the Pay People draft, show pay addable again" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    staff_pay!(hours: 5)
    line = show_pay!(200)
    batch = PayoutBatch.current_open_draft(org)

    PayoutBatchService.discard!(batch)

    draft = JSON.parse(PayDraft.read(org))
    expect(draft["lines"].keys).to eq([ member.id.to_s ])
    expect(draft["lines"][member.id.to_s]).not_to have_key("bonus") # the show line didn't leak in
    expect(ledger("performer")).to eq(20_000) # still owed for the show
    expect(ledger("staffing")).to eq(0)       # staff earnings reversed with their lines

    PerformerPayoutRunService.add_show_payout!(line.show_payout)
    expect(PayoutBatch.current_open_draft(org).items.sole.amount_cents).to eq(20_000)
  end

  it "stages everyone owed onto the open run by kind, without paying anything twice" do
    batch = staff_pay!(hours: 5)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning",
                            amount_cents: 7_000, category: "performer", description: "old earning")

    expect(PayoutBatchService.build_for(organization: org)).to eq(batch)
    item = batch.reload.items.sole
    balance_lines = item.payout_contributions.where(label: "Balance payout")
    expect(balance_lines.pluck(:category, :amount_cents)).to eq([ [ "performer", 7_000 ] ]) # staff pay already on the run
    expect(item.amount_cents).to eq(17_000)

    PayoutBatchService.build_for(organization: org)
    expect(batch.reload.items.sole.amount_cents).to eq(17_000)
  end

  # A draft from before the merge is the org's open run now, carrying every
  # kind of money — it mustn't keep calling itself "Staffing" on the run page
  # and on payees' deposit receipts.
  it "relabels open drafts as plain payout runs, leaving paid and course runs as they were" do
    open_staff = org.payout_batches.create!(kind: "staff_pay", status: "draft", trigger: "manual")
    funded = org.payout_batches.create!(kind: "performer", status: "funded", trigger: "manual")
    course = org.payout_batches.create!(kind: "course", status: "draft", trigger: "manual")

    ActiveRecord::Migration.suppress_messages { LabelOpenRunsAsPayouts.new.up }

    expect(open_staff.reload.kind).to eq("payout")
    expect(open_staff.kind_label).to eq("Payouts")
    expect(funded.reload.kind).to eq("performer")
    expect(course.reload.kind).to eq("course")
  end

  describe "folding the open drafts left from before the merge" do
    # The database now allows one open run per org; recreate the old world.
    before do
      ActiveRecord::Base.connection.execute("DROP INDEX idx_payout_batches_one_open_run_per_org")
    end

    it "moves every line into the oldest draft and leaves the ledger alone" do
      show_pay!(200)
      performer_run = PayoutBatch.current_open_draft(org)
      performer_run.update_columns(kind: "performer")
      staff_run = org.payout_batches.create!(kind: "staff_pay", status: "draft", trigger: "manual")
      staff_item = staff_run.items.create!(payee: person, amount_cents: 10_000)
      StaffPayRunService.add_contribution!(staff_run, staff_item, person, label: "Worked hours (5h)", amount_cents: 10_000)
      entry = create(:staff_time_entry, organization: org, person: person)
      entry.update_columns(payout_batch_id: staff_run.id)
      ledger_before = PayoutLedgerEntry.where(organization: org).pluck(:id, :amount_cents).sort

      PayoutDraftFolder.fold_all!

      expect(PayoutBatch.exists?(staff_run.id)).to be(false)
      item = performer_run.reload.items.sole
      expect(item.payout_contributions.pluck(:category).sort).to eq(%w[performer staffing])
      expect(item.amount_cents).to eq(30_000)
      expect(performer_run.total_cents).to eq(30_000)
      expect(entry.reload.payout_batch_id).to eq(performer_run.id)
      expect(PayoutLedgerEntry.where(organization: org).pluck(:id, :amount_cents).sort).to eq(ledger_before)

      expect(PayoutDraftFolder.fold_all!).to eq([]) # idempotent
    end
  end
end

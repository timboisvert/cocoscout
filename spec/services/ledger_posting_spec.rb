# frozen_string_literal: true

require "rails_helper"

# The books: every money event is one balanced, permanent journal entry, and
# a source re-posting restates its entry instead of doubling it.
RSpec.describe LedgerPosting do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  # Any record can be a source; a show stands in for a ticket order here.
  let(:source) { show }

  def sale(cents: 2_000, fee: 138)
    [
      { account: :cocoscout_balance, amount_cents: cents - fee },
      { account: :ticketing_fees, amount_cents: fee },
      { account: :advance_ticket_sales, amount_cents: -cents, show: show, production: production }
    ]
  end

  def post_sale(**options)
    described_class.post!(organization: org, source: source, kind: "sale",
                          entry_date: Date.new(2026, 10, 10), cash_date: Date.new(2026, 10, 1),
                          memo: "Ticket sale", lines: sale(**options))
  end

  describe ChartOfAccounts do
    it "gives an org its accounts on first use, once" do
      expect { ChartOfAccounts.ensure!(org) }.to change { org.ledger_accounts.count }.from(0).to(ChartOfAccounts::SYSTEM.size)
      expect { ChartOfAccounts.ensure!(org) }.not_to(change { org.ledger_accounts.count })

      income = ChartOfAccounts.account(org, :ticket_income)
      expect([ income.name, income.account_type, income.system ]).to eq([ "Ticket income", "income", true ])
    end

    it "won't delete an account every org has" do
      account = ChartOfAccounts.account(org, :bank)
      expect(account.destroy).to be(false)
      expect(LedgerAccount.exists?(account.id)).to be(true)
    end
  end

  it "posts one balanced entry with its dimensions" do
    entry = post_sale

    expect(entry.balanced?).to be(true)
    expect(entry.journal_lines.count).to eq(3)
    deferred = entry.journal_lines.find_by(ledger_account: ChartOfAccounts.account(org, :advance_ticket_sales))
    expect([ deferred.amount_cents, deferred.show_id, deferred.production_id ]).to eq([ -2_000, show.id, production.id ])
    expect(described_class.trial_balance(org).values.sum).to eq(0)
  end

  it "refuses lines that don't balance, and writes nothing" do
    lines = [ { account: :bank, amount_cents: 100 }, { account: :other_income, amount_cents: -99 } ]
    expect {
      described_class.post!(organization: org, source: source, kind: "x", entry_date: Date.current, lines: lines)
    }.to raise_error(LedgerPosting::Unbalanced)
    expect(JournalEntry.count).to eq(0)
  end

  it "does nothing when the same thing is posted again" do
    first = post_sale
    expect { post_sale }.not_to(change { JournalEntry.count })
    expect(post_sale).to eq(first)
  end

  it "restates a changed posting by reversing the old entry, never editing it" do
    original = post_sale(fee: 138)
    restated = post_sale(fee: 150)

    expect(original.reload).to be_reversed
    expect(original.reversal.journal_lines.sum(:amount_cents)).to eq(0)
    expect(original.reversal.journal_lines.pluck(:amount_cents)).to match_array(original.journal_lines.pluck(:amount_cents).map(&:-@))
    expect(JournalEntry.live.where(source_id: show.id, kind: "sale")).to eq([ restated ])
    expect(ChartOfAccounts.account(org, :ticketing_fees).balance_cents).to eq(150)
    expect(described_class.trial_balance(org).values.sum).to eq(0)
  end

  it "withdraws an entry when there's nothing left to post, and on unpost!" do
    post_sale
    described_class.post!(organization: org, source: source, kind: "sale", entry_date: Date.current,
                          lines: [ { account: :bank, amount_cents: 0 }, { account: :other_income, amount_cents: 0 } ])
    expect(JournalEntry.live.where(kind: "sale")).to be_empty
    expect(ChartOfAccounts.account(org, :cocoscout_balance).balance_cents).to eq(0)

    post_sale
    described_class.unpost!(source: source, kind: "sale")
    expect(JournalEntry.live.where(kind: "sale")).to be_empty
    expect(described_class.unpost!(source: source, kind: "sale")).to be_nil
  end

  it "keeps posted entries and lines permanent" do
    entry = post_sale
    expect { entry.update!(memo: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { entry.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { entry.journal_lines.first.update!(amount_cents: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "counts accrual on the day it's earned and cash on the day money moved" do
    post_sale
    deferred = ChartOfAccounts.account(org, :advance_ticket_sales)

    # Sold Oct 1 for an Oct 10 show.
    expect(deferred.natural_balance_cents(as_of: Date.new(2026, 10, 5), basis: :cash)).to eq(2_000)
    expect(deferred.natural_balance_cents(as_of: Date.new(2026, 10, 5), basis: :accrual)).to eq(0)
    expect(deferred.natural_balance_cents(as_of: Date.new(2026, 10, 10), basis: :accrual)).to eq(2_000)
  end

  it "never posts to another organization's account" do
    theirs = ChartOfAccounts.account(create(:organization), :bank)
    lines = [ { account: theirs, amount_cents: 100 }, { account: :other_income, amount_cents: -100 } ]
    expect {
      described_class.post!(organization: org, source: source, kind: "x", entry_date: Date.current, lines: lines)
    }.to raise_error(ArgumentError, /another organization/)
  end

  it "clears an organization's books when the organization is deleted" do
    post_sale
    post_sale(fee: 150)
    org.destroy!
    expect([ JournalLine.count, JournalEntry.count, LedgerAccount.count ]).to eq([ 0, 0, 0 ])
  end
end

# frozen_string_literal: true

require "rails_helper"

# Month-end balances (Books V1.3): a balance is the finished months, kept a
# row per account per month, plus the lines dated since. Whatever is kept,
# every answer is the one adding up every line would give.
RSpec.describe BooksBalances do
  let(:org) { create(:organization, :pro) }
  let(:today) { Date.current }
  let(:this_month) { today.beginning_of_month }

  def post!(cents, earned:, moved: earned, from: :bank, to: :ticket_income)
    LedgerPosting.post!(organization: org, source: nil, kind: "sale", entry_date: earned, cash_date: moved,
                        lines: [ { account: from, amount_cents: cents }, { account: to, amount_cents: -cents } ])
  end

  # Every line, added up the long way.
  def long_way(basis, from, to)
    column = basis == :cash ? "cash_date" : "entry_date"
    lines = JournalLine.where(organization_id: org.id).joins(:journal_entry)
    lines = lines.where.not(journal_entries: { cash_date: nil }) if basis == :cash
    lines = lines.where("journal_entries.#{column} >= ?", from) if from
    lines = lines.where("journal_entries.#{column} <= ?", to) if to
    lines.group(:ledger_account_id).sum(:amount_cents).transform_values(&:to_i).reject { |_, c| c.zero? }
  end

  def expect_every_span_right
    edges = [ nil, this_month << 7, (this_month << 5) + 9, (this_month << 5).end_of_month, this_month << 4, (this_month << 3) + 14,
              (this_month << 2) - 1, this_month << 2, (this_month << 1) + 3, this_month - 1, this_month, today, today + 40 ]
    %i[accrual cash].each do |basis|
      edges.each do |from|
        edges.each do |to|
          next if from && to && from > to

          got = described_class.sums(org, basis: basis, from: from, to: to).reject { |_, c| c.zero? }
          expect(got).to eq(long_way(basis, from, to)), "#{basis} #{from.inspect}..#{to.inspect}: #{got} vs #{long_way(basis, from, to)}"
        end
      end
    end
  end

  before do
    post!(10_000, earned: (this_month << 6) + 4)
    post!(2_500, earned: (this_month << 5) + 9, moved: (this_month << 4) + 2)
    post!(700, earned: (this_month << 5).end_of_month, moved: nil, from: :owed_to_you)
    post!(4_000, earned: (this_month << 3) + 14, from: :venue, to: :bank)
    post!(1_200, earned: (this_month << 1) + 3, moved: this_month + 1)
    post!(900, earned: today)
    post!(333, earned: today + 20, moved: today)
  end

  it "answers the same before any month is kept, after the roll, and after more is posted" do
    expect(described_class.rolled_through(org.id)).to be_nil
    expect_every_span_right

    # The roll stops a full month short of today.
    months = described_class.roll!(org)
    expect(described_class.rolled_through(org.id)).to eq((this_month << 1) - 1)
    expect(months).to eq(5)
    expect(LedgerMonthBalance.where(organization: org).pluck(:month).uniq.sort).to eq([ this_month << 6, this_month << 5, this_month << 4, this_month << 3 ])
    expect_every_span_right
    # Nothing to do twice.
    expect(described_class.roll!(org)).to eq(0)

    # This month and last month are never kept, so posting there moves nothing.
    post!(50, earned: today)
    post!(60, earned: this_month - 2)
    expect(described_class.rolled_through(org.id)).to eq((this_month << 1) - 1)
    expect_every_span_right
  end

  it "reads the kept months, not their lines" do
    described_class.roll!(org)
    bank = ChartOfAccounts.account(org, :bank)
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("journal_lines") }
    balance = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { bank.balance_cents }
    expect(balance).to eq(long_way(:accrual, nil, nil)[bank.id])
    # One read of the lines, and only those dated after the kept months.
    expect(queries.size).to eq(1)
    expect(queries.first).to include("journal_entries.entry_date >=")
    expect(bank.natural_balance_cents(basis: :cash, as_of: (this_month << 3) + 20)).to eq(long_way(:cash, nil, (this_month << 3) + 20)[bank.id])
  end

  it "stops trusting a kept month the moment something is posted into it, and keeps it again on the next roll" do
    described_class.roll!(org)
    # Earned in a kept month.
    entry = post!(800, earned: (this_month << 4) + 10, moved: today)
    expect(described_class.rolled_through(org.id)).to eq((this_month << 4) - 1)
    expect_every_span_right
    expect(described_class.roll!(org)).to eq(3)
    expect_every_span_right

    # Money that moved in a kept month, earned now.
    post!(90, earned: today, moved: (this_month << 5) + 1)
    expect(described_class.rolled_through(org.id)).to eq((this_month << 5) - 1)
    expect_every_span_right
    described_class.roll!(org)

    # A reversal lands on the entry's own dates.
    LedgerPosting.reverse!(entry)
    expect(described_class.rolled_through(org.id)).to eq((this_month << 4) - 1)
    expect_every_span_right
    described_class.roll!(org)
    expect_every_span_right
    expect(described_class.verify!(org)).to eq([])
  end

  it "throws the kept months away when they disagree with the lines" do
    described_class.roll!(org)
    row = LedgerMonthBalance.where(organization: org).first
    row.update_columns(accrual_cents: row.accrual_cents + 1)
    expect(described_class.verify!(org)).to eq([ row.ledger_account_id ])
    expect(described_class.rolled_through(org.id)).to be_nil
    expect(LedgerMonthBalance.where(organization: org)).to be_empty
    expect_every_span_right
  end

  it "is checked and rolled by the nightly job, and the statements read the same either way" do
    statements = -> { BooksStatements.new(org.reload) }
    totals = lambda do
      s = statements.call
      range = (this_month << 5)..today
      [ s.balance_sheet(today).sections.map(&:total_cents), s.balance_sheet((this_month << 3) + 20).sections.map(&:total_cents),
        s.profit_and_loss(range).sections.map(&:total_cents), s.profit_and_loss(range, by_production: true).sections.map(&:total_cents),
        s.cash_flow(range).sections.map(&:total_cents), BooksStatements.new(org, basis: :cash).profit_and_loss(range).sections.map(&:total_cents),
        BooksReport.new(org).groups.map(&:last), BooksReport.new(org, basis: :cash).groups.map(&:last), BooksReport.new(org).trial_balance_cents ]
    end
    before_roll = totals.call
    BooksReconciliationJob.perform_now
    expect(described_class.rolled_through(org.id)).to eq((this_month << 1) - 1)
    expect(totals.call).to eq(before_roll)
    expect(before_roll.last).to eq(0)
  end
end

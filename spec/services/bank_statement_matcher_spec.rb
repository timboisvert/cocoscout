# frozen_string_literal: true

require "rails_helper"

# Books → Bank matching (plan D3): the bank's description picks between
# same-amount entries, and one deposit can be a group of entries.
RSpec.describe BankStatementMatcher do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let(:import) { org.bank_statement_imports.create!(imported_by: owner, filename: "oct.csv", format: "csv", lines_count: 0, status: "matching") }

  def line(on, cents, description)
    import.bank_statement_lines.create!(organization: org, on: on, amount_cents: cents, description: description)
  end

  it "is sure when the description names the entry and clearly ahead of another with the same amount" do
    lumber = org.money_records.create!(kind: "out", on: Date.new(2026, 10, 2), amount_cents: 24_000, category_key: "production", counterparty: "Chicago Lumber Co.", via: "bank", recorded_by: owner)
    org.money_records.create!(kind: "out", on: Date.new(2026, 10, 9), amount_cents: 24_000, category_key: "production", counterparty: "Ace Hardware", via: "bank", recorded_by: owner)
    bank = line(Date.new(2026, 10, 5), -24_000, "CHICAGO LUMBER CO 4411")
    unnamed = line(Date.new(2026, 10, 12), -24_000, "CARD PURCHASE 9920")

    result = described_class.run!(org)
    expect(result.matched).to eq(1)
    expect(result.suggested).to eq(1)
    expect(bank.reload.state).to eq("matched")
    expect(bank.journal_line.journal_entry.source).to eq(lumber)
    # The other one is only near in time: a suggestion, to the entry that is left.
    expect(unnamed.reload.state).to eq("suggested")
    expect(unnamed.journal_line.journal_entry.source.counterparty).to eq("Ace Hardware")
  end

  it "suggests the one group of entries that adds up to a deposit, and leaves a line with nothing open" do
    [ [ 1, 10_000 ], [ 3, 25_000 ], [ 5, 40_000 ], [ 6, 7_500 ] ].each do |day, cents|
      org.money_records.create!(kind: "in", on: Date.new(2026, 10, day), amount_cents: cents, category_key: "sponsorship", counterparty: "HotTix", via: "bank", recorded_by: owner)
    end
    deposit = line(Date.new(2026, 10, 8), 75_000, "HOTTIX LLC PAYMENTS")
    stray = line(Date.new(2026, 10, 9), 1_234, "SOMETHING ELSE")

    result = described_class.run!(org)
    expect(result.suggested).to eq(1)
    expect(deposit.reload.state).to eq("suggested")
    expect(deposit.journal_lines.sum(:amount_cents)).to eq(75_000)
    expect(deposit.journal_line_ids.size).to eq(3)
    expect(stray.reload.state).to eq("open")

    # Confirmed, the three lines on the books are taken; the next run skips them.
    deposit.match!(deposit.journal_lines.to_a)
    again = line(Date.new(2026, 10, 10), 75_000, "HOTTIX LLC PAYMENTS")
    described_class.run!(org)
    expect(again.reload.state).to eq("open")
  end
end

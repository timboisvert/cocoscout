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
  describe "a statement coming in" do
    let(:october) { org.bank_statement_imports.create!(imported_by: owner, filename: "oct.csv", format: "csv", lines_count: 0, status: "matching") }

    def record(on, cents, payee)
      org.money_records.create!(kind: "out", on: on, amount_cents: cents, category_key: "production", counterparty: payee, via: "bank", recorded_by: owner)
    end

    it "looks again at an older open line only when the books gained something near it since the last statement" do
      import.update!(status: "ready", matched_at: 1.hour.ago)
      # On the books before the last statement was matched: nothing new to say about it.
      before = record(Date.new(2026, 6, 2), 9_900, "Old Vendor")
      JournalLine.where(journal_entry_id: before.journal_entries.map(&:id)).update_all(created_at: 2.hours.ago)
      march = line(Date.new(2026, 3, 10), -5_000, "ACE HARDWARE 221")
      june = line(Date.new(2026, 6, 3), -9_900, "OLD VENDOR")
      mine = october.bank_statement_lines.create!(organization: org, on: Date.new(2026, 10, 5), amount_cents: -1_200, description: "COFFEE")
      since = org.bank_statement_imports.where.not(id: october.id).maximum(:matched_at)

      expect(described_class.lines_to_match(org, october, since: since)).to contain_exactly(mine)

      # Someone records the March purchase: that line is worth another look, June's still isn't.
      record(Date.new(2026, 3, 9), 5_000, "Ace Hardware")
      expect(described_class.lines_to_match(org, october, since: since)).to contain_exactly(mine, march)
      # Before any statement was ever matched, every open line.
      expect(described_class.lines_to_match(org, october, since: nil)).to contain_exactly(mine, march, june)

      BankStatementMatchJob.perform_now(october.id)
      expect(march.reload.state).to eq("matched")
      expect(june.reload.state).to eq("open")
      expect(october.reload.matched_at).to be_within(1.minute).of(Time.current)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrgCashEntry, type: :model do
  let(:organization) { create(:organization) }
  let(:person) { create(:person) }

  def credit!(amount, org: organization, source: nil, entry_type: "adjustment")
    described_class.post!(organization: org, entry_type: entry_type,
                          amount_cents: amount, source: source)
  end

  describe ".post! / .unpost!" do
    let(:registration) { create(:course_registration) }

    it "re-posting the same source restates the amount instead of duplicating" do
      described_class.post!(organization: organization, entry_type: "course_registration",
                            amount_cents: 900, source: registration)
      described_class.post!(organization: organization, entry_type: "course_registration",
                            amount_cents: 850, source: registration)

      entries = described_class.where(source: registration)
      expect(entries.count).to eq(1)
      expect(entries.first.amount_cents).to eq(850)
    end

    it "allows different entry types for the same source" do
      described_class.post!(organization: organization, entry_type: "course_registration",
                            amount_cents: 900, source: registration)
      described_class.post!(organization: organization, entry_type: "refund",
                            amount_cents: -900, source: registration)

      expect(described_class.where(source: registration).count).to eq(2)
      expect(described_class.balance_cents(organization)).to eq(0)
    end

    it "unpost! removes only the matching entry type and is a safe no-op otherwise" do
      described_class.post!(organization: organization, entry_type: "course_registration",
                            amount_cents: 900, source: registration)

      expect(described_class.unpost!(source: registration, entry_type: "refund")).to eq(0)
      expect(described_class.unpost!(source: registration, entry_type: "course_registration")).to eq(1)
      expect(described_class.balance_cents(organization)).to eq(0)
    end

    it "rejects unknown entry types" do
      expect {
        described_class.post!(organization: organization, entry_type: "bogus", amount_cents: 1)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe ".available_cents" do
    it "subtracts unpaid items on funded performer/staff runs (committed money)" do
      credit!(10_000)

      batch = create(:payout_batch, organization: organization, kind: "performer",
                     status: "processing", funding_status: "succeeded")
      batch.items.create!(payee: person, amount_cents: 3_000, status: "pending")
      batch.items.create!(payee: person, amount_cents: 1_000, status: "failed")
      batch.items.create!(payee: person, amount_cents: 2_000, status: "paid")

      expect(described_class.balance_cents(organization)).to eq(10_000)
      expect(described_class.committed_cents(organization)).to eq(4_000)
      expect(described_class.available_cents(organization)).to eq(6_000)
    end

    it "does not count course-run items or unfunded runs as committed" do
      credit!(10_000)

      course = create(:payout_batch, organization: organization, kind: "course", status: "processing")
      course.items.create!(payee: person, amount_cents: 3_000, status: "pending")
      draft = create(:payout_batch, organization: organization, kind: "performer", status: "draft")
      draft.items.create!(payee: person, amount_cents: 2_000, status: "pending")

      expect(described_class.available_cents(organization)).to eq(10_000)
    end

    it "is per-organization" do
      other_org = create(:organization)
      credit!(5_000)
      credit!(9_000, org: other_org)

      expect(described_class.balance_cents(organization)).to eq(5_000)
      expect(described_class.balance_cents(other_org)).to eq(9_000)
    end
  end

  describe ".debit!" do
    let(:batch) { create(:payout_batch, organization: organization, kind: "course", status: "processing") }
    let(:item) { batch.items.create!(payee: person, amount_cents: 4_000, status: "pending") }

    before do
      allow(described_class).to receive(:enforcement_enabled?).and_return(true)
    end

    it "posts a negative entry when the balance covers it" do
      credit!(10_000)

      described_class.debit!(organization: organization, amount_cents: 4_000, source: item)

      expect(described_class.balance_cents(organization)).to eq(6_000)
      entry = described_class.find_by(source: item, entry_type: "transfer")
      expect(entry.amount_cents).to eq(-4_000)
    end

    it "raises InsufficientFunds without posting when the balance can't cover it" do
      credit!(3_000)

      expect {
        described_class.debit!(organization: organization, amount_cents: 4_000, source: item)
      }.to raise_error(OrgCashEntry::InsufficientFunds)
      expect(described_class.balance_cents(organization)).to eq(3_000)
    end

    it "never blocks another org's balance from being spent" do
      other_org = create(:organization)
      credit!(1_000)
      credit!(100_000, org: other_org)

      expect {
        described_class.debit!(organization: organization, amount_cents: 4_000, source: item)
      }.to raise_error(OrgCashEntry::InsufficientFunds)
    end

    it "skips the availability check when enforce: false (source_transaction-pinned)" do
      credit!(100)

      described_class.debit!(organization: organization, amount_cents: 4_000, source: item, enforce: false)

      expect(described_class.balance_cents(organization)).to eq(-3_900)
    end

    it "skips the availability check when the kill switch is off" do
      allow(described_class).to receive(:enforcement_enabled?).and_return(false)
      credit!(100)

      described_class.debit!(organization: organization, amount_cents: 4_000, source: item)

      expect(described_class.balance_cents(organization)).to eq(-3_900)
    end

    it "a retry of an already-debited source restates instead of failing or double-debiting" do
      credit!(4_000)
      described_class.debit!(organization: organization, amount_cents: 4_000, source: item)

      # Balance is now 0, but the retry re-reserves the same money.
      described_class.debit!(organization: organization, amount_cents: 4_000, source: item)

      expect(described_class.where(source: item, entry_type: "transfer").count).to eq(1)
      expect(described_class.balance_cents(organization)).to eq(0)
    end
  end

  # Real threads need real (committed) rows and separate DB connections, so this
  # example opts out of the wrapping transaction (uses_transaction) and cleans
  # up after itself.
  describe ".debit! under concurrency" do
    uses_transaction "serializes concurrent debits so only one of two racing draws wins"

    it "serializes concurrent debits so only one of two racing draws wins", no_transaction: true do
      allow(described_class).to receive(:enforcement_enabled?).and_return(true)
      org = create(:organization)
      payee = create(:person)
      batch = create(:payout_batch, organization: org, kind: "course", status: "processing")
      items = 2.times.map { batch.items.create!(payee: payee, amount_cents: 4_000, status: "pending") }
      credit!(4_000, org: org)

      results = Queue.new
      barrier = Queue.new
      threads = items.map do |i|
        Thread.new do
          barrier.pop
          described_class.debit!(organization: org, amount_cents: 4_000, source: i)
          results << :ok
        rescue OrgCashEntry::InsufficientFunds
          results << :insufficient
        end
      end
      2.times { barrier << true }
      threads.each(&:join)

      expect(2.times.map { results.pop }.sort).to eq(%i[insufficient ok])
      expect(described_class.balance_cents(org)).to eq(0)
    ensure
      described_class.where(organization: org).delete_all if org
      batch&.destroy
      payee&.destroy
      org&.destroy
    end
  end
end

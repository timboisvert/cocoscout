# frozen_string_literal: true

require "rails_helper"

# My Payments with years of pay behind it: the history stops at its newest
# HISTORY_LIMIT, the year's total doesn't, and neither asks the database
# once per payment.
RSpec.describe MyPaymentsSummary do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let(:year) { Date.current.year }

  def paid_item!(cents, at)
    batch = create(:payout_batch, organization: org, status: "completed")
    PayoutBatchItem.create!(payout_batch: batch, payee: person, amount_cents: cents, status: "paid", paid_at: at, deposited_at: at + 2.days)
  end

  it "adds up everything sent this year, past where the history stops" do
    stub_const("MyPaymentsSummary::HISTORY_LIMIT", 3)
    5.times { |i| paid_item!(10_000, Time.zone.local(year, 1, 5 + i, 12)) }
    paid_item!(7_700, Time.zone.local(year - 1, 12, 30, 12))

    summary = described_class.new(person)
    expect(summary.payments.size).to eq(3)
    expect(summary.payments.map(&:paid_at)).to eq(summary.payments.map(&:paid_at).sort.reverse)
    expect(summary.payments.first.paid_at.to_date).to eq(Date.new(year, 1, 9))
    expect(summary.paid_this_year_cents).to eq(50_000)
    expect(summary.paid_this_year_cents(year - 1)).to eq(7_700)
    expect(summary.sent_total_cents).to eq(57_700)
  end

  it "knows a first payment without asking per payment" do
    first = paid_item!(10_000, Time.zone.local(year, 1, 5, 12))
    later = paid_item!(10_000, Time.zone.local(year, 2, 5, 12))
    [ first, later ].each { |item| item.update_columns(deposited_at: nil) }

    payments = described_class.new(person).payments
    # The provider holds a first payment longer: its expected date is later
    # than a couple of business days after it was sent.
    by_id = payments.index_by(&:id)
    expect(by_id[first.id].expected_on).to eq(first.reload.expected_deposit_date)
    expect(by_id[later.id].expected_on).to eq(later.reload.expected_deposit_date)
    expect(by_id[first.id].expected_on - first.paid_at.to_date).to be > (by_id[later.id].expected_on - later.paid_at.to_date)

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("payout_batch_items") && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.new(person).payments }
    expect(queries.size).to be <= 3
  end
end

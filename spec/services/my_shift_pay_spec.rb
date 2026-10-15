# frozen_string_literal: true

require "rails_helper"

# The Getting paid card on My Shifts, in the payee's words (Tim, 2026-10-15):
# waiting for approval, approved, on its way, deposited. Fae's question was
# when the money would actually arrive; "paid Oct 11" and "$0.00 owed" said
# it already had.
RSpec.describe MyShiftPay do
  let(:org) { create(:organization, name: "FUNHAÜS") }
  let(:person) { create(:person, name: "Fae Staffer") }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2_000) }

  def worked(day, hours, approved: true)
    starts = Time.zone.local(2026, 10, day, 18)
    create(:staff_time_entry, organization: org, person: person, started_at: starts, ended_at: starts + hours.hours,
                              approved_at: approved ? starts + 1.day : nil)
  end

  def run(status:, payday: nil)
    org.payout_batches.create!(kind: "performer", status: status, trigger: "manual", total_cents: 0, payday: payday)
  end

  # A payment we sent: its run, its entries, our transfer on paid_at.
  def sent(entries, paid_at:, deposited_at: nil)
    batch = run(status: "completed")
    entries.each { |e| e.update_columns(payout_batch_id: batch.id, paid_at: paid_at) }
    batch.items.create!(payee: person, amount_cents: entries.sum { |e| (e.hours * 2_000).round }, status: "paid",
                        paid_at: paid_at, stripe_transfer_id: "tr_#{SecureRandom.hex(4)}", deposited_at: deposited_at)
  end

  before do
    # Not their first payment: September's was deposited on the 30th.
    sent([ worked(1, 4).tap { |e| e.update_columns(started_at: Time.zone.local(2026, 9, 26, 18)) } ],
         paid_at: Time.zone.local(2026, 9, 28, 10), deposited_at: Time.zone.local(2026, 9, 30))
  end

  it "puts what's on its way first, with the day it's due, and owes nothing it already sent" do
    sent([ worked(8, 4.5), worked(9, 6), worked(10, 6) ], paid_at: Time.zone.local(2026, 10, 11, 10))

    travel_to(Time.zone.local(2026, 10, 12, 12)) do
      pay = described_class.new([ person.id ])
      expect(pay.hero).to have_attributes(stage: :on_its_way, cents: 33_000, on: Date.new(2026, 10, 13),
                                          sent_on: Date.new(2026, 10, 11), org: "FUNHAÜS")
      expect(pay.still_to_be_paid_cents).to eq(0)
      expect(pay.days.first(3).map { |d| [ d.date.day, d.stage, d.cents ] })
        .to eq([ [ 10, :on_its_way, 12_000 ], [ 9, :on_its_way, 12_000 ], [ 8, :on_its_way, 9_000 ] ])
      expect(pay.days.last).to have_attributes(stage: :deposited, on: Date.new(2026, 9, 30))
    end
  end

  it "shows approved pay next, each waiting day once, then what's waiting when that's all" do
    worked(13, 6)
    waiting = worked(14, 3, approved: false)

    travel_to(Time.zone.local(2026, 10, 15, 12)) do
      pay = described_class.new([ person.id ])
      expect(pay.hero).to have_attributes(stage: :approved, cents: 12_000, on: nil)
      expect(pay.days.first(2).map(&:stage)).to eq(%i[waiting approved])
    end

    StaffTimeEntry.where.not(id: waiting.id).where(payout_batch_id: nil).delete_all
    travel_to(Time.zone.local(2026, 10, 15, 12)) do
      expect(described_class.new([ person.id ]).hero).to have_attributes(stage: :waiting, cents: 6_000, hours: 3)
    end
  end

  it "names the run's payday for approved pay already in a run" do
    batch = run(status: "draft", payday: Date.new(2026, 10, 16))
    worked(13, 6).update_columns(payout_batch_id: batch.id, paid_at: Time.current)
    batch.items.create!(payee: person, amount_cents: 12_000, status: "pending")

    travel_to(Time.zone.local(2026, 10, 15, 12)) do
      pay = described_class.new([ person.id ])
      expect(pay.hero).to have_attributes(stage: :approved, cents: 12_000, on: Date.new(2026, 10, 16))
      expect(pay.days.first).to have_attributes(stage: :approved, on: Date.new(2026, 10, 16))
    end
  end

  it "adds each day's card tips to that day, so the days add up to the deposit" do
    entries = [ worked(9, 6), worked(10, 6) ]
    item = sent(entries, paid_at: Time.zone.local(2026, 10, 11, 10))
    tips = [ { "date" => "2026-10-09", "amount_cents" => 3_545 }, { "date" => "2026-10-10", "amount_cents" => 2_000 } ]
    PayoutContribution.create!(payout_batch: item.payout_batch, payout_batch_item: item, payee: person, category: "staffing",
                               label: "Tips", amount_cents: 5_545, worksheet: tips)
    PayoutContribution.create!(payout_batch: item.payout_batch, payout_batch_item: item, payee: person, category: "staffing",
                               label: "Cash tips (recorded)", amount_cents: 4_000, excluded_from_payout: true,
                               worksheet: [ { "date" => "2026-10-10", "amount_cents" => 4_000 } ])

    travel_to(Time.zone.local(2026, 10, 12, 12)) do
      days = described_class.new([ person.id ]).days.first(2)
      expect(days.map { |d| [ d.date.day, d.cents, d.tips_cents ] }).to eq([ [ 10, 14_000, 2_000 ], [ 9, 15_545, 3_545 ] ])
    end
  end

  it "puts a tips total with no worksheet on the run's one day" do
    item = sent([ worked(10, 6) ], paid_at: Time.zone.local(2026, 10, 11, 10))
    PayoutContribution.create!(payout_batch: item.payout_batch, payout_batch_item: item, payee: person, category: "staffing",
                               label: "Tips", amount_cents: 1_500)

    travel_to(Time.zone.local(2026, 10, 12, 12)) do
      expect(described_class.new([ person.id ]).days.first).to have_attributes(cents: 13_500, tips_cents: 1_500)
    end
  end

  it "says deposited once the payout provider says so, and only sent when it never does" do
    item = sent([ worked(10, 6) ], paid_at: Time.zone.local(2026, 10, 11, 10))

    travel_to(Time.zone.local(2026, 10, 20, 12)) do
      pay = described_class.new([ person.id ])
      expect(pay.hero).to have_attributes(stage: :caught_up, settled_as: :sent, on: Date.new(2026, 10, 11))
      expect(pay.days.first).to have_attributes(stage: :sent, on: Date.new(2026, 10, 11))
    end

    item.update!(deposited_at: Time.zone.local(2026, 10, 13))
    travel_to(Time.zone.local(2026, 10, 20, 12)) do
      pay = described_class.new([ person.id ])
      expect(pay.hero).to have_attributes(stage: :caught_up, settled_as: :deposited, on: Date.new(2026, 10, 13), cents: 12_000)
      expect(pay.days.first).to have_attributes(stage: :deposited, on: Date.new(2026, 10, 13))
    end
  end
end

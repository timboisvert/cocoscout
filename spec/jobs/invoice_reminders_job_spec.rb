# frozen_string_literal: true

require "rails_helper"

# An invoice's own reminders (Tim, 2026-11-09): every invoice offered "3
# days before, and when overdue" and showed it, and nothing sent them. They
# go by themselves now, once each, only for an invoice that was emailed, and
# any send in a reminder's days counts as it.
RSpec.describe InvoiceRemindersJob do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let(:due) { Date.new(2026, 12, 15) }

  def invoice(sent_on: due - 10, reminders: "before_and_overdue", due_on: due)
    made = org.invoices.create!(bill_to_name: "Acme Bank", bill_to_email: "ap@acme.test", issued_on: due_on - 20, due_on: due_on, category_key: "sponsorship",
                                reminders: reminders, created_by: owner,
                                invoice_lines_attributes: [ { description: "Season sponsorship", quantity: "1", unit: "1500.00" } ])
    made.update_columns(sent_at: sent_on.in_time_zone(org.time_zone.presence || Time.zone).change(hour: 12), sent_count: 1) if sent_on
    made
  end

  # The job at 9 in the morning, Central, on a day; the emails it sent.
  def run_on(day)
    ActionMailer::Base.deliveries.clear
    travel_to(Time.find_zone("America/Chicago").local(day.year, day.month, day.day, 9)) do
      perform_enqueued_jobs { described_class.perform_now }
    end
    ActionMailer::Base.deliveries.dup
  end

  it "reminds three days before it's due and once when it's overdue, and never twice" do
    sponsor = invoice
    expect(run_on(due - 4)).to be_empty

    mail = run_on(due - 3)
    expect(mail.map(&:to)).to eq([ [ "ap@acme.test" ] ])
    expect(mail.first.subject).to include("Reminder", sponsor.display_number, "$1,500.00", "December 15, 2026")
    expect(sponsor.reload.sent_count).to eq(2)
    expect(run_on(due - 3)).to be_empty
    expect(run_on(due - 2)).to be_empty
    expect(run_on(due)).to be_empty

    expect(run_on(due + 1).size).to eq(1)
    expect(sponsor.reload.sent_count).to eq(3)
    expect(run_on(due + 2)).to be_empty
    expect(run_on(due + 8)).to be_empty
  end

  it "catches up when a morning was missed, inside the days a reminder belongs to" do
    invoice
    expect(run_on(due - 2).size).to eq(1)
    # Overdue, found five days late; found a month late, it's left alone.
    expect(run_on(due + 5).size).to eq(1)
    later = invoice(due_on: due + 60, sent_on: due + 40)
    expect(run_on(due + 60 + 20)).to be_empty
    expect(later.reload.sent_count).to eq(1)
  end

  it "only reminds when overdue for an invoice set to that, and never for one set to none" do
    invoice(reminders: "overdue")
    quiet = invoice(reminders: "none")
    expect(run_on(due - 3)).to be_empty
    expect(run_on(due + 1).size).to eq(1)
    expect(quiet.reload.sent_count).to eq(1)
  end

  it "leaves alone an invoice that was never emailed, has no address, is paid or is cancelled" do
    never_sent = invoice(sent_on: nil)
    no_address = invoice.tap { |i| i.update_columns(bill_to_email: nil) }
    paid = invoice.tap { |i| i.receive!(on: due - 5, amount_cents: 150_000, via: "check") }
    void = invoice.tap { |i| i.void!("Made by mistake") }
    expect(run_on(due - 3)).to be_empty
    expect(run_on(due + 1)).to be_empty
    expect([ never_sent, no_address, paid, void ].map { |i| i.reload.next_reminder_on(due - 3) }).to all(be_nil)
  end

  it "counts a manager's own send as the reminder" do
    # Sent two days before it was due: they only just got it, so no "before" reminder.
    late = invoice(sent_on: due - 2)
    expect(run_on(due - 1)).to be_empty
    expect(late.next_reminder_on(due - 1)).to eq(due + 1)
    # Sent again by hand after the due date: that was the overdue reminder.
    late.update_columns(sent_at: (due + 1).in_time_zone("America/Chicago").change(hour: 8), sent_count: 2)
    expect(run_on(due + 1)).to be_empty
    expect(run_on(due + 2)).to be_empty
  end

  it "says what is still owed once part is paid" do
    part = invoice
    part.receive!(on: due - 6, amount_cents: 50_000, via: "check")
    mail = run_on(due - 3)
    expect(mail.first.subject).to include("$1,000.00")
    expect(mail.first.subject).not_to include("$1,500.00")
  end

  it "reads the day in the organization's own time zone" do
    org.update!(time_zone: "Pacific Time (US & Canada)")
    invoice
    # Three days before it's due has begun in Chicago, not yet in Los Angeles.
    ActionMailer::Base.deliveries.clear
    travel_to(Time.find_zone("America/Chicago").local(2026, 12, 12, 1)) { perform_enqueued_jobs { described_class.perform_now } }
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(run_on(due - 3).size).to eq(1)
  end

  it "says on the invoice when the next one goes" do
    sponsor = invoice
    travel_to(Time.find_zone("America/Chicago").local(2026, 12, 8, 12)) do
      expect(sponsor.next_reminder_on).to eq(due - 3)
      expect(invoice(sent_on: nil).next_reminder_on).to be_nil
    end
  end
end

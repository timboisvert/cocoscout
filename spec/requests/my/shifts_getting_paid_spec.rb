# frozen_string_literal: true

require "rails_helper"

# The Getting paid card and tiles on My Shifts say where pay stands, in the
# payee's words (Tim, 2026-10-15): nothing reads "paid" or "$0 owed" while the
# money is still on its way to their bank.
RSpec.describe "Getting paid on My Shifts", type: :request do
  let(:password) { "Password123!" }
  let(:org) { create(:organization, name: "FUNHAÜS") }
  let(:me) { create(:user, password: password) }
  let!(:person) do
    create(:person, user: me, stripe_account_id: "acct_fae", payouts_enabled: true, stripe_account_status: "enabled")
      .tap { |p| me.update!(default_person: p) }
  end
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2_000) }

  before { post handle_signin_path, params: { email_address: me.email_address, password: password } }

  def text(body) = body.gsub(/\s+/, " ")

  it "says it's on its way and when it's due, not paid, with a plain bank line" do
    started = 3.days.ago.change(hour: 18)
    entry = create(:staff_time_entry, organization: org, person: person, started_at: started, ended_at: started + 6.hours,
                                      approved_at: 2.days.ago)
    batch = org.payout_batches.create!(kind: "performer", status: "completed", trigger: "manual", total_cents: 12_000)
    entry.update_columns(payout_batch_id: batch.id, paid_at: 1.day.ago)
    batch.items.create!(payee: person, amount_cents: 12_000, status: "paid", paid_at: 1.day.ago, stripe_transfer_id: "tr_fae")

    get my_shifts_path
    html = text(response.body)
    expect(html).to include("Getting paid", "On its way", "$120.00", "Expected in your bank about", "Still to be paid", "Nothing right now")
    expect(html).to include("Paid to your bank", "Change", "All my payments")
    expect(html).not_to include("Estimated from", "Owed for staffing hours", "Bank connected", "paid #{1.day.ago.strftime('%b %-d')}", "Est. pay owed")
  end

  it "asks for a bank with the house alert when pay is waiting on one" do
    person.update!(payouts_enabled: false, stripe_account_status: nil, stripe_account_id: nil)
    started = 2.days.ago.change(hour: 18)
    create(:staff_time_entry, organization: org, person: person, started_at: started, ended_at: started + 3.hours,
                              approved_at: 1.day.ago)

    get my_shifts_path
    html = text(response.body)
    expect(html).to include("Ready for you", "$60.00 is approved", "Add your bank")
    expect(response.body).to include("data-alert-panel")
  end
end

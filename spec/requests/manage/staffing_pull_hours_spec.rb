# frozen_string_literal: true

require "rails_helper"

# The bulk "Pull in approved hours" entry point on Pay People. It writes the
# same hidden inputs the per-person modal writes, so the server side is
# unchanged — these specs cover what the page offers and that a bulk-pulled
# run prices identically to the per-person path.
RSpec.describe "Pay People — pull in approved hours", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:role) { create(:house_role, organization: org, name: "Bartender", default_hourly_rate_cents: 2000) }

  def staff!(name)
    person = create(:person, name: name)
    org.people << person unless org.people.exists?(person.id)
    member = create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000)
    create(:staff_role_qualification, organization_staff_member: member, house_role: role, hourly_rate_cents: 2000)
    [ person, member ]
  end

  def approved_entry!(person, hours:)
    org.staff_time_entries.create!(person: person, house_role: role, hours: hours,
                                   started_at: 2.days.ago, ended_at: 2.days.ago + hours.hours,
                                   approved_at: Time.current, approved_by: owner)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers the pull when someone has approved hours, naming the total" do
    person, = staff!("Sam Staffer")
    approved_entry!(person, hours: 3)

    get manage_staffing_pay_path

    expect(response.body).to include("Pull in approved hours")
    expect(response.body).to include("approved hours waiting")
    expect(response.body).to include("Sam Staffer")
  end

  it "stays out of the way when nothing is approved" do
    staff!("Sam Staffer")

    get manage_staffing_pay_path
    expect(response.body).not_to include("Pull in approved hours")
  end

  it "leaves pending hours out — approval stays a deliberate act" do
    person, = staff!("Sam Staffer")
    org.staff_time_entries.create!(person: person, house_role: role, hours: 4,
                                   started_at: 1.day.ago, ended_at: 1.day.ago + 4.hours)

    get manage_staffing_pay_path
    expect(response.body).not_to include("Pull in approved hours")
  end

  it "prices a bulk-pulled run exactly like the per-person path" do
    person, member = staff!("Sam Staffer")
    entry = approved_entry!(person, hours: 3)

    post manage_staffing_pay_path, params: {
      payday: Date.current.to_s,
      lines: { member.id.to_s => { "time_entry_ids" => [ entry.id.to_s ] } }
    }

    batch = PayoutBatch.order(:created_at).last
    expect(batch).to be_present
    expect(batch.items.sum(&:amount_cents)).to eq(6000) # 3h x $20
    expect(entry.reload.payout_batch_id).to eq(batch.id)
    expect(entry.paid_at).to be_present
  end
end

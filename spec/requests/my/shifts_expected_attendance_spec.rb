# frozen_string_literal: true

require "rails_helper"

# My → Shifts: under each shift, the shows it covers and how many people to
# expect at each (ShiftExpectedAttendance), when the organization shows it
# (Staffing settings → Ticketing). Just the number, no names, no money.
RSpec.describe "My::Shifts expected attendance", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Quinn") }
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:membership) { create(:organization_staff_member, organization: org, person: person) }
  let!(:bar) { create(:house_role, organization: org, name: "Bartender") }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show_at) { 1.week.from_now.change(hour: 19, min: 30) }
  let!(:show) { create(:show, production: production, date_and_time: show_at, duration_minutes: 120) }
  let!(:rehearsal) { create(:show, :rehearsal, production: production, date_and_time: show_at - 6.hours, duration_minutes: 90) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }

  def shift_for(starts_at, ends_at, source: nil)
    shift = create(:shift, organization: org, house_role: bar, starts_at: starts_at, ends_at: ends_at, source: source)
    shift.shift_assignments.create!(person: person, position: 1)
    shift
  end

  before do
    TicketingProfile.for(org).update!(enabled: true)
    StaffingFinalization.create!(organization: org, week_start: show_at.to_date.beginning_of_week, finalized_at: Time.current)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com", buyer_phone: "312-555-0100")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Abe Comp", email: nil, tier: general, quantity: 1) ], by: owner, email_them: false)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "lists the show a shift is tied to with how many to expect, comps included, and nothing else" do
    shift_for(show_at - 1.hour, show_at + 3.hours, source: show)
    get my_shifts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("7:30 PM Stargazers", "3 expected")
    expect(response.body).not_to include("Dana Scully", "Covering", "$3,000", "$30")
    expect(response.body).not_to include("1:30 PM Stargazers rehearsal")
  end

  it "lists every show a house shift overlaps, a rehearsal by name with no count" do
    shift_for(show_at - 7.hours, show_at + 3.hours)
    get my_shifts_path
    lines = response.body.scan(/data-show-line>\s*<span[^>]*>([^<]+)<\/span>(?:[^<]*<span[^>]*>([^<]+)<\/span>)?/).map { |a, b| [ a.strip, b&.strip ] }
    expect(lines).to eq([ [ "1:30 PM Stargazers rehearsal", nil ], [ "7:30 PM Stargazers", "3 expected" ] ])
  end

  it "shows no count when the organization turns it off, or its box office is closed" do
    shift_for(show_at - 1.hour, show_at + 3.hours, source: show)
    org.update!(staff_see_ticket_counts: false)
    get my_shifts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("expected")

    org.update!(staff_see_ticket_counts: true)
    TicketingProfile.for(org).update!(enabled: false)
    get my_shifts_path
    expect(response.body).not_to include("expected")
  end

  it "draws nothing under a house shift with no show on" do
    shift_for(show_at + 1.day, show_at + 1.day + 4.hours)
    get my_shifts_path
    expect(response.body).not_to include("data-show-line", "expected")
  end
end

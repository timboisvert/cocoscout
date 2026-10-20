# frozen_string_literal: true

require "rails_helper"

# Ticketing settings → Notifications has a row for each way tickets go out
# (Tim, 2026-10-19): each online sale, each door sale, each comp issued, each
# pass redeemed, each with its own email.
RSpec.describe TicketingAfterSaleJob do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let(:tier) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40) }
  let(:seller) { create(:user).tap { |u| u.update!(default_person: create(:person, user: u, name: "Robin Door")) } }

  let(:calls) { [] }

  before do
    allow(TicketingNotifier).to receive(:notify) { |_org, kind, variables:| calls << [ kind, variables ] }
    allow(TicketingMilestones).to receive(:check!)
  end

  def paid(channel, buyer_name: nil, seats: 1)
    create(:ticket_order, ticket_listing: listing, channel: channel, status: "paid", buyer_name: buyer_name, buyer_email: nil, issued_by: seller).tap do |order|
      seats.times { order.tickets.create!(ticket_tier: tier, ticket_listing: listing, status: "valid", price_cents: 2_000) }
    end
  end

  def notified(kind)
    calls.select { |k, _| k == kind }.map(&:last)
  end

  it "sends online and website sales as each online sale" do
    described_class.perform_now(paid("online", buyer_name: "Avery").id)
    described_class.perform_now(paid("embed").id)
    expect(notified(:sale).size).to eq(2)
  end

  it "sends tap, scan to pay and cash at the door as each door sale, saying who sold it and how it was paid" do
    %w[door_tap door_card door_cash].each { |channel| described_class.perform_now(paid(channel).id) }
    sales = notified(:door_sale)
    expect(sales.map { |v| v[:payment_method] }).to eq([ "a tapped card or phone", "scan to pay", "cash" ])
    expect(sales.first).to include(seller_name: "Robin Door", buyer_name: "", ticket_count: "1 ticket")
    expect(sales.flat_map(&:values).join).not_to include("Stripe", "iPhone")
  end

  it "sends comps given together as one each-comp-issued email naming everyone" do
    a = paid("comp", buyer_name: "Sam Guest", seats: 2)
    b = paid("comp", buyer_name: "Lee Guest")
    described_class.perform_now(b.id, together: [ a.id, b.id ])
    comps = notified(:comp_issued)
    expect(comps.size).to eq(1)
    expect(comps.first).to include(giver_name: "Robin Door", ticket_count: "3 comps", recipients: "Sam Guest (2) and Lee Guest (1)")
  end

  it "sends a pass used online or at the door as each pass redeemed" do
    described_class.perform_now(paid("pass", buyer_name: "Pat Pass").id)
    described_class.perform_now(paid("door_pass").id)
    redeemed = notified(:pass_redeemed)
    expect(redeemed.map { |v| v[:where_used] }).to eq(%w[online at\ the\ door])
    expect(redeemed.first).to include(holder_name: "Pat Pass")
  end

  it "stays quiet for an unpaid order" do
    described_class.perform_now(create(:ticket_order, ticket_listing: listing, channel: "door_tap", status: "pending").id)
    expect(calls).to be_empty
  end

  it "ticks door sales for whoever ticked each sale before (the migration)" do
    require Rails.root.join("db/migrate/20261020010000_add_door_comp_pass_notifications.rb").to_s
    ticked = TicketingProfile.for(org).tap { |p| p.update!(notification_rules: { "sale" => [ "user:#{seller.id}" ] }) }
    other = TicketingProfile.for(create(:organization, :pro)).tap { |p| p.update!(notification_rules: { "daily_summary" => [ "user:1" ] }) }
    ActiveRecord::Migration.suppress_messages { AddDoorCompPassNotifications.new.up }
    expect(ticked.reload.notification_rules["door_sale"]).to eq([ "user:#{seller.id}" ])
    expect(other.reload.notification_rules).not_to have_key("door_sale")
  end

  it "has an email for every kind" do
    TicketingTemplates.ensure!
    expect(ContentTemplate.where(key: TicketingNotifications::KEYS.map { |k| "ticketing_#{k}" }).count).to eq(TicketingNotifications::KEYS.size)
  end
end

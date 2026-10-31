# frozen_string_literal: true

require "rails_helper"

# Pricing rules (advanced ticketing plan §7c, V1.4 step 5): rules a manager
# writes move a type's price as a date sells or nears, within its floor and
# ceiling; the first matching rule wins; buyers pay the price in effect and
# keep it; the hourly job logs each flip.
RSpec.describe "Ticket pricing rules", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let!(:location) { create(:location, organization: org, name: "The Lodge") }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let!(:general) { setup.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10, position: 0) }
  let!(:vip) { setup.ticket_tiers.create!(name: "VIP", price_cents: 5_000, quantity: 10, position: 1) }
  let!(:show) { create(:show, production: production, location: location, date_and_time: 20.days.from_now.change(hour: 19)) }
  let(:listing) { ProductionTicketingDates.sync!(setup); TicketListing.find_by!(show: show) }
  let(:date_general) { listing.ticket_tiers.find_by!(source_tier_id: general.id) }
  let(:date_vip) { listing.ticket_tiers.find_by!(source_tier_id: vip.id) }
  let(:url) { manage_update_production_ticketing_path(production, section: "pricing") }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "moves prices by the first matching rule within the floor and ceiling, sells at the price in effect, and logs the flips" do
    get manage_edit_production_ticketing_path(production, section: "pricing")
    expect(response.body).to include("Pricing rules", "No rules yet")

    # Last week: everything $5 more. Slow seller: General 25% off a week out under 50% sold.
    patch url, params: { pricing_action: "add", rule: { name: "Last week", condition: "days_out_at_most", days: 7, change_kind: "amount", change_value: "5" } }
    patch url, params: { pricing_action: "add", rule: { name: "Early birds", condition: "sold_pct_at_least", threshold: 0, ticket_tier_id: general.id, change_kind: "amount", change_value: "-5" } }
    patch url, params: { pricing_action: "limits", limits: { vip.id => { floor: "", ceiling: "52" }, general.id => { floor: "18", ceiling: "" } } }
    rules = setup.price_rules.in_order.to_a
    expect(rules.map(&:name)).to eq([ "Last week", "Early birds" ])
    expect(rules.first.change_value).to eq(500)
    expect(vip.reload.price_ceiling_cents).to eq(5_200)
    expect(general.reload.price_floor_cents).to eq(1_800)
    expect(date_general.reload.price_floor_cents).to eq(1_800)

    # Twenty days out: Last week doesn't fit; Early birds fits General (0% sold or more, floor $18).
    expect(TicketPricing.current_price_cents(listing, date_general)).to eq(1_800)
    expect(TicketPricing.current_price_cents(listing, date_vip)).to eq(5_000)
    get manage_edit_production_ticketing_path(production, section: "pricing")
    expect(response.body).to include("Right now", "$18.00", "Early birds")

    # Six days out: Last week comes first and wins; VIP stops at its ceiling.
    travel_to(show.date_and_time - 6.days) do
      expect(TicketPricing.current_price_cents(listing, date_general)).to eq(2_500)
      expect(TicketPricing.current_price_cents(listing, date_vip)).to eq(5_200)
      get tickets_event_path(org: profile.slug, event: listing.slug)
      expect(response.body).to include("data-price=\"2500\"", "data-price=\"5200\"")
      order = TicketCheckout.start!(listing: listing, quantities: { date_general.id.to_s => "1", date_vip.id.to_s => "1" })
      expect(order.tickets.map(&:price_cents)).to contain_exactly(2_500, 5_200)
      order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_rules")
      expect(order.reload.status).to eq("paid")
      expect(Ticketing::ListingPayload.for(listing).dig(:tiers, 0, :price_cents)).to eq(2_500)
      expect(Ticketing::ListingPayload.for(listing).dig(:tiers, 0, :list_price_cents)).to eq(2_000)

      TicketPriceChangeJob.perform_now
      changes = TicketPriceChange.where(ticket_listing: listing).order(:ticket_tier_id)
      expect(changes.map { |c| [ c.ticket_tier.name, c.from_cents, c.to_cents, c.ticket_price_rule&.name ] })
        .to contain_exactly([ "General", 2_000, 2_500, "Last week" ], [ "VIP", 5_000, 5_200, "Last week" ])
      TicketPriceChangeJob.perform_now
      expect(TicketPriceChange.where(ticket_listing: listing).count).to eq(2)
    end

    # Rules move, switch off and go.
    patch url, params: { pricing_action: "down", rule_id: rules.first.id }
    expect(setup.price_rules.in_order.map(&:name)).to eq([ "Early birds", "Last week" ])
    fresh = -> { TicketListing.find(listing.id) }
    travel_to(show.date_and_time - 6.days) { expect(TicketPricing.current_price_cents(fresh.call, date_general)).to eq(1_800) }
    patch url, params: { pricing_action: "toggle", rule_id: rules.last.id }
    expect(rules.last.reload.enabled).to be(false)
    expect(TicketPricing.current_price_cents(fresh.call, date_general)).to eq(2_000)
    patch url, params: { pricing_action: "remove", rule_id: rules.last.id }
    expect(setup.price_rules.count).to eq(1)

    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "prices by how far sold" do
    patch url, params: { pricing_action: "add", rule: { name: "Nearly full", condition: "sold_pct_at_least", threshold: 50, change_kind: "percent", change_value: "10" } }
    expect(TicketPricing.current_price_cents(listing, date_vip)).to eq(5_000)
    order = TicketCheckout.start!(listing: listing, quantities: { date_vip.id.to_s => "10" })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_half")
    # 10 of 20 sold: 50%.
    expect(TicketPricing.current_price_cents(listing.reload, date_general)).to eq(2_200)
  end
end

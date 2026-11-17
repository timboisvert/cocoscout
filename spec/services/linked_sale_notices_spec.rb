# frozen_string_literal: true

require "rails_helper"

# Through a connected contract, the contractor's organization chooses who on
# its side is notified as tickets sell and comps are given (Tim, 2026-11-17):
# person by person, counts only, never an email, and each person can switch
# theirs off.
RSpec.describe LinkedSaleNotices do
  let!(:owner) { create(:user) }
  let!(:venue) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:location) { create(:location, organization: venue) }
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, name: "Thea Example").tap { |p| user.update!(default_person: p) } }
  let!(:theirs) { create(:organization, :pro, owner: user, name: "The Holly Problem") }
  let!(:contractor) { create(:contractor, organization: venue, person: person, name: "Thea Example") }
  let!(:production) { create(:production, organization: venue, production_type: "third_party", name: "The Holly Problem") }
  let!(:contract) do
    create(:contract, :active, organization: venue, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let(:night) { 3.weeks.from_now.in_time_zone(venue.time_zone).change(hour: 20, min: 0) }
  let!(:rental) { contract.space_rentals.create!(location: location, starts_at: night, ends_at: night + 2.hours, confirmed: true) }
  let!(:contract_show) { production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental) }
  let!(:their_production) { create(:production, organization: theirs, name: "The Holly Problem") }
  let!(:connection) do
    request = ContractConnections.request!(contract: contract, user: user, organization: theirs, production: their_production)
    ContractConnections.accept!(request, user: owner)
  end
  # Someone on the production's team, and someone in its cast only.
  let!(:teammate) { create(:user).tap { |u| create(:person, user: u, name: "Riley Team") } }
  let!(:listing) do
    TicketingProfile.for(venue).update!(enabled: true)
    create(:ticket_listing, organization: venue, production: production, show: contract_show, status: "on_sale")
  end
  let!(:tier) { listing.ticket_tiers.first || listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40) }

  before do
    create(:organization_role, user: teammate, organization: theirs, company_role: "member")
    ProductionPermission.create!(user: teammate, production: their_production, role: "manager")
  end

  def sale!(quantity = 2)
    order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => quantity.to_s })
    order.update!(buyer_name: "Dana Whitfield", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(4)}", charge_id: "ch_#{SecureRandom.hex(4)}")
    order
  end

  it "lists who can be chosen: who runs the organization, its production team, and the people on the contract" do
    names = described_class.candidates(connection).map { |candidate| [ candidate.name, candidate.role ] }
    expect(names).to eq([ [ "Thea Example", "Owner" ], [ "Riley Team", "Production team manager" ] ])
  end

  it "notifies only the people chosen, with how many and how full, and never the buyer's name" do
    described_class.choose!(connection, [ teammate.id ], by: user)

    order = sale!(2)
    expect { described_class.after_sale(:sale, [ order ]) }
      .to change(teammate.notifications, :count).by(1).and change(user.notifications, :count).by(0)

    notice = teammate.notifications.last
    expect(notice.title).to match(/\A2 tickets sold for The Holly Problem, \w{3} \w{3} \d+\. 2 of 40 sold\.\z/)
    expect(notice.title).not_to include("Dana")
    expect(notice.path).to eq(Rails.application.routes.url_helpers.manage_production_sale_path(their_production, listing))
  end

  it "says comps as comps" do
    described_class.choose!(connection, [ user.id ], by: user)
    orders = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "A Friend", email: nil, tier: tier, quantity: 1) ], by: owner, note: nil, email_them: false)

    expect { described_class.after_sale(:comp_issued, orders) }.to change(user.notifications, :count).by(1)
    expect(user.notifications.last.title).to start_with("1 comp given for The Holly Problem")
  end

  it "says nothing about a door sale, to someone who switched theirs off, or once the seller stops sharing" do
    described_class.choose!(connection, [ user.id, teammate.id ], by: user)
    order = sale!

    expect { described_class.after_sale(:door_sale, [ order ]) }.not_to change(Notification, :count)

    watcher = connection.watchers.find_by!(user: teammate)
    described_class.set_muted!(teammate, watcher.id, true)
    expect { described_class.after_sale(:sale, [ order ]) }.to change(user.notifications, :count).by(1).and change(teammate.notifications, :count).by(0)

    contract.update!(shares_ticket_sales: false)
    expect { described_class.after_sale(:sale, [ order ]) }.not_to change(Notification, :count)
  end

  it "only takes people who can see the sales, and drops someone who is taken off" do
    stranger = create(:user)
    described_class.choose!(connection, [ teammate.id, stranger.id ], by: user)
    expect(connection.watchers.pluck(:user_id)).to eq([ teammate.id ])

    described_class.choose!(connection, [], by: user)
    expect(connection.watchers).to be_empty
  end

  it "stops for someone who has left the production's team, though still ticked" do
    described_class.choose!(connection, [ teammate.id ], by: user)
    ProductionPermission.where(user: teammate).destroy_all

    expect { described_class.after_sale(:sale, [ sale! ]) }.not_to change(teammate.notifications, :count)
  end
end

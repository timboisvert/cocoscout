# frozen_string_literal: true

require "rails_helper"

# Tim, 2026-10-07: an amendment removed a 9:00 night and added 9:30, and both
# stayed, on the calendar and in Ticketing. The removed night's show quietly
# refused to go (its listing had a canceled comp), the booking went anyway,
# and the show lived on cut loose from the contract. Now:
#  - "sold" means money taken or a ticket still good; abandoned checkouts and
#    comps given back go with the date;
#  - a show that won't go stops the amendment;
#  - a night's time changes in place ("Change time"), keeping its buyers.
RSpec.describe "Contract nights that sold tickets", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }
  let(:nine) { 3.weeks.from_now.change(hour: 21) }
  let!(:rental) { contract.space_rentals.create!(location: location, starts_at: nine - 1.hour, ends_at: nine + 2.hours, event_starts_at: nine, event_ends_at: nine + 90.minutes, confirmed: true) }
  let!(:show) { production.shows.create!(date_and_time: nine, duration_minutes: 90, location: location, space_rental: rental) }
  let!(:listing) do
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
    setup = production.reload.production_ticketing
    setup.update!(event_matching: "manual")
    setup.production_ticketing_shows.find_or_create_by!(show: show)
    show.reload.ticket_listing || TicketListing.create!(show: show, status: "on_sale")
  end
  let(:general) { listing.ticket_tiers.first || listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def comp_given_back!
    order = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Walter", email: nil, tier: general, quantity: 2) ], by: owner, email_them: false).first
    TicketOrderRefund.issue!(order, by: owner, notify: false)
    order.reload
  end

  def abandoned_checkout!
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" })
    order.update!(status: "expired")
    order
  end

  def paid_order!
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(4)}")
    order.reload
  end

  def stage_amendment!(removed: [], moved: {}, new_bookings: [])
    contract.update_amend_data(contract.amend_data.merge("removed_rental_ids" => removed, "moved_rentals" => moved, "new_bookings" => new_bookings))
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "removes a night whose only orders are a comp given back and an abandoned checkout: show, listing, booking and pick all go" do
    comp = comp_given_back!
    checkout = abandoned_checkout!
    expect(comp).to have_attributes(status: "refunded", money_path: "none")
    expect(listing.worth_keeping?).to be(false)

    stage_amendment!(removed: [ rental.id ])
    post apply_amendments_manage_contract_path(contract)

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(Show.exists?(show.id)).to be(false)
    expect(TicketListing.exists?(listing.id)).to be(false)
    expect(SpaceRental.exists?(rental.id)).to be(false)
    expect(ProductionTicketingShow.where(show_id: show.id)).to be_empty
    expect(TicketOrder.where(id: [ comp.id, checkout.id ])).to be_empty
  end

  it "refuses to remove a night someone paid for, and keeps it whole" do
    paid_order!
    stage_amendment!(removed: [ rental.id ])

    post apply_amendments_manage_contract_path(contract)

    expect(response).to redirect_to(amend_review_manage_contract_path(contract))
    expect(flash[:alert]).to include("use Change time on the night instead")
    expect([ Show.exists?(show.id), SpaceRental.exists?(rental.id), TicketListing.exists?(listing.id) ]).to eq([ true, true, true ])
  end

  it "never deletes the booking when the show won't go" do
    allow_any_instance_of(Show).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new("Failed to destroy", show))
    stage_amendment!(removed: [ rental.id ])

    post apply_amendments_manage_contract_path(contract)

    expect(flash[:alert]).to start_with("Couldn't remove one of the nights, so nothing changed")
    expect(SpaceRental.exists?(rental.id)).to be(true)
    expect(show.reload.space_rental_id).to eq(rental.id)
  end

  it "moves a night to a new time in place from Change the deal, keeping its buyers" do
    order = paid_order!
    get amend_bookings_manage_contract_path(contract)
    expect(response.body).to include("Change time", %(name="moved[#{rental.id}]"))

    post save_amend_bookings_manage_contract_path(contract), params: {
      booking_mode: "multiple", booking_rules_json: "[]", removed_rental_ids: "[]",
      moved: { rental.id.to_s => (rental.starts_at + 30.minutes).strftime("%Y-%m-%dT%H:%M") }
    }
    expect(contract.reload.amend_data["moved_rentals"].keys).to eq([ rental.id.to_s ])

    get amend_events_manage_contract_path(contract)
    expect(response.body).to include("will move to a new time", "Moved")
    get amend_review_manage_contract_path(contract)
    expect(response.body).to include("Events to Move (1)", "1 moved")

    post apply_amendments_manage_contract_path(contract)

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(show.reload.date_and_time).to eq(nine + 30.minutes)
    expect(rental.reload.starts_at).to eq(nine - 30.minutes)
    expect(show.ticket_listing.id).to eq(listing.id)
    expect(order.reload.status).to eq("paid")
    expect(TicketShowChange.pending?(listing.reload)).to be(true)
    expect(production.shows.count).to eq(1)
  end

  it "ignores a move on a night that's also being removed" do
    post save_amend_bookings_manage_contract_path(contract), params: {
      booking_mode: "multiple", booking_rules_json: "[]", removed_rental_ids: [ rental.id ].to_json,
      moved: { rental.id.to_s => (rental.starts_at + 30.minutes).strftime("%Y-%m-%dT%H:%M") }
    }
    expect(contract.reload.amend_data["moved_rentals"]).to eq({})
  end

  describe "Change the dates → Remove" do
    it "deletes a night with nothing sold, its ticketing pick included" do
      abandoned_checkout!

      post apply_amend_dates_manage_contract_path(contract), params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(flash[:notice]).to eq("Removed #{rental.starts_at.strftime('%b %-d')}.")
      expect(Show.exists?(show.id)).to be(false)
      expect(TicketListing.exists?(listing.id)).to be(false)
    end

    it "cancels a night people hold tickets for, so they can be refunded" do
      paid_order!
      get amend_dates_manage_contract_path(contract)
      expect(response.body).to include("People hold tickets for this night")

      post apply_amend_dates_manage_contract_path(contract), params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(show.reload.canceled).to be(true)
      expect(TicketListing.exists?(listing.id)).to be(true)
      expect(flash[:notice]).to include("stays on the calendar as cancelled")
    end
  end

  it "lets Shows & Events delete a date whose only order is a comp given back" do
    comp_given_back!

    delete manage_delete_show_path(production, show)

    expect(Show.exists?(show.id)).to be(false)
    expect(TicketListing.exists?(listing.id)).to be(false)
  end
end

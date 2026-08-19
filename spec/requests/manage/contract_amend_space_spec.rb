# frozen_string_literal: true

require "rails_helper"

# Changing the room is smaller than changing the dates: the contract names the
# venue, not the space, so nothing about the money or the paperwork moves.
RSpec.describe "Contracts — change the room", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:mainstage) { location.location_spaces.create!(name: "Mainstage") }
  let!(:cabaret) { location.location_spaces.create!(name: "Cabaret") }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  let(:future) { 3.weeks.from_now.change(hour: 20) }

  def booked_date!(starts_at, space: mainstage)
    rental = contract.space_rentals.create!(location: location, location_space: space, starts_at: starts_at,
                                            ends_at: starts_at + 2.hours, confirmed: true)
    show = production.shows.create!(date_and_time: starts_at, duration_minutes: 120,
                                    location: location, location_space: space, space_rental: rental)
    [ rental, show ]
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "is offered alongside changing the dates and changing the deal" do
    get amend_choose_manage_contract_path(contract)

    expect(response.body).to include("Change the room")
    expect(response.body).to include("Change the dates")
    expect(response.body).to include("Change the deal")
  end

  it "lists every date with the venue's rooms to choose from" do
    booked_date!(future)

    get amend_space_manage_contract_path(contract)

    expect(response.body).to include("Mainstage")
    expect(response.body).to include("Cabaret")
    expect(response.body).to include("Entire Venue")
  end

  # The point of the feature: a run of nights moves rooms in one pass.
  it "moves a run of dates into another room, and the shows follow" do
    rental_a, show_a = booked_date!(future)
    rental_b, show_b = booked_date!(future + 1.week)

    post apply_amend_space_manage_contract_path(contract),
         params: { spaces: { rental_a.id.to_s => cabaret.id.to_s, rental_b.id.to_s => cabaret.id.to_s } }

    expect(rental_a.reload.location_space_id).to eq(cabaret.id)
    expect(rental_b.reload.location_space_id).to eq(cabaret.id)
    expect(show_a.reload.location_space_id).to eq(cabaret.id)
    expect(show_b.reload.location_space_id).to eq(cabaret.id)
    expect(flash[:notice]).to include("Cabaret")
  end

  it "leaves the dates, the deal and the payments exactly as they were" do
    rental, show = booked_date!(future)
    payment = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                 due_date: future.to_date, show_id: show.id)
    versions_before = contract.contract_versions.count

    expect {
      post apply_amend_space_manage_contract_path(contract),
           params: { spaces: { rental.id.to_s => cabaret.id.to_s } }
    }.not_to change { contract.contract_payments.count }

    expect(rental.reload.starts_at.to_i).to eq(future.to_i)
    expect(payment.reload.amount).to eq(200)
    expect(payment.due_date).to eq(future.to_date)
    expect(contract.contract_versions.count).to eq(versions_before)
  end

  it "moves a date to the whole venue when no room is picked" do
    rental, show = booked_date!(future)

    post apply_amend_space_manage_contract_path(contract),
         params: { spaces: { rental.id.to_s => "" } }

    expect(rental.reload.location_space_id).to be_nil
    expect(show.reload.location_space_id).to be_nil
    expect(flash[:notice]).to include("Entire Venue")
  end

  it "says so plainly when nothing was actually changed" do
    rental, = booked_date!(future)

    post apply_amend_space_manage_contract_path(contract),
         params: { spaces: { rental.id.to_s => mainstage.id.to_s } }

    expect(flash[:notice]).to eq("No room changes to make.")
  end

  describe "when the room is already taken" do
    let!(:other_contract) { create(:contract, :active, organization: org) }

    before do
      other_contract.space_rentals.create!(location: location, location_space: cabaret,
                                           starts_at: future, ends_at: future + 2.hours, confirmed: true)
    end

    it "warns instead of moving" do
      rental, = booked_date!(future)

      post apply_amend_space_manage_contract_path(contract),
           params: { spaces: { rental.id.to_s => cabaret.id.to_s } }

      expect(response.body).to include("Something else is already in there")
      expect(response.body).to include("Change it anyway")
      expect(rental.reload.location_space_id).to eq(mainstage.id)
    end

    it "moves it anyway when told to, and leaves the other booking alone" do
      rental, = booked_date!(future)

      post apply_amend_space_manage_contract_path(contract),
           params: { spaces: { rental.id.to_s => cabaret.id.to_s }, force: "1" }

      expect(rental.reload.location_space_id).to eq(cabaret.id)
      expect(other_contract.space_rentals.first.location_space_id).to eq(cabaret.id)
    end

    # An entire-venue move swallows every room, so it clashes with anything at
    # the venue — the same rule SpaceRental applies on create.
    it "counts an entire-venue move as clashing with any room" do
      rental, = booked_date!(future)

      post apply_amend_space_manage_contract_path(contract),
           params: { spaces: { rental.id.to_s => "" } }

      expect(response.body).to include("Something else is already in there")
      expect(rental.reload.location_space_id).to eq(mainstage.id)
    end
  end

  # A night that's already happened was in the room it was in.
  describe "dates that have already happened" do
    let(:past) { 2.weeks.ago.change(hour: 20) }

    it "aren't listed" do
      booked_date!(past)
      booked_date!(future)

      get amend_space_manage_contract_path(contract)

      expect(response.body).to include(future.strftime("%A, %b %-d, %Y"))
      expect(response.body).not_to include(past.strftime("%A, %b %-d, %Y"))
    end

    it "can't be moved even if one is posted" do
      rental, show = booked_date!(past)

      post apply_amend_space_manage_contract_path(contract),
           params: { spaces: { rental.id.to_s => cabaret.id.to_s } }

      expect(rental.reload.location_space_id).to eq(mainstage.id)
      expect(show.reload.location_space_id).to eq(mainstage.id)
      expect(flash[:notice]).to eq("No room changes to make.")
    end

    it "says so when the whole contract is behind us" do
      booked_date!(past)

      get amend_space_manage_contract_path(contract)

      expect(response.body).to include("Every date on this contract has already happened")
    end
  end

  # A crafted id from another venue mustn't quietly read as "entire venue".
  it "ignores a room that isn't one of this venue's" do
    other_location = create(:location, organization: org)
    foreign_space = other_location.location_spaces.create!(name: "Someone else's room")
    rental, = booked_date!(future)

    post apply_amend_space_manage_contract_path(contract),
         params: { spaces: { rental.id.to_s => foreign_space.id.to_s } }

    expect(rental.reload.location_space_id).to eq(mainstage.id)
    expect(flash[:notice]).to eq("No room changes to make.")
  end
end

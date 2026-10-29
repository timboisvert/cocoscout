# frozen_string_literal: true

require "rails_helper"

# Removing a contract's dates says what it leaves behind — tickets people hold,
# staff scheduled — and never deals with any of it itself (Tim, 2026-10-29:
# "Don't actually manually do it, just tell me what I need to do"). The manager
# says they'll take care of it, the dates go as they always have, and the list
# sits on the contract page until it's done.
RSpec.describe "Contracts — what removing dates leaves to do", type: :request do
  include ActionView::Helpers::NumberHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }
  let(:nine) { 3.weeks.from_now.change(hour: 21) }
  let!(:rental) { contract.space_rentals.create!(location: location, starts_at: nine - 1.hour, ends_at: nine + 2.hours, confirmed: true) }
  let!(:show) { production.shows.create!(date_and_time: nine, duration_minutes: 90, location: location, space_rental: rental) }
  let(:label) { rental.starts_at.strftime("%a, %b %-d") }

  def ticketing_on!
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
    setup = production.reload.production_ticketing
    setup.update!(event_matching: "manual")
    setup.production_ticketing_shows.find_or_create_by!(show: show)
    show.reload.ticket_listing || TicketListing.create!(show: show, status: "on_sale")
  end

  def paid_order!(listing)
    tier = listing.ticket_tiers.first
    order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => "2" })
    order.update!(buyer_name: "Dana", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(4)}")
    order.reload
  end

  def comps!(listing)
    tier = listing.ticket_tiers.first
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Walter", email: nil, tier: tier, quantity: 3) ], by: owner, email_them: false).first
  end

  def bartender_scheduled!
    role = create(:house_role, organization: org, name: "Bartender")
    shift = create(:shift, organization: org, house_role: role, source: show,
                           starts_at: nine - 1.hour, ends_at: nine + 3.hours)
    create(:shift_assignment, shift: shift, person: create(:person, name: "Ana Ruiz"))
  end

  def remove_params
    { dates: { rental.id.to_s => { action: "remove" } } }
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "Change dates → review" do
    it "says plainly when nothing is affected, and asks for no acknowledgement" do
      ticketing_on!

      get review_amend_dates_manage_contract_path(contract), params: remove_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No tickets sold and nobody scheduled for this date.")
      expect(response.body).not_to include("I'll take care of these")
      expect(response.body).not_to include('data-controller="acknowledge-gate"')
    end

    it "leaves tickets out when ticketing isn't on for the date" do
      get review_amend_dates_manage_contract_path(contract), params: remove_params

      expect(response.body).to include("Nobody is scheduled to work this date.")
      expect(response.body).not_to include("tickets sold")
    end

    it "lists the tickets people hold and who's scheduled, with where to fix each, behind an acknowledgement" do
      listing = ticketing_on!
      order = paid_order!(listing)
      comps!(listing)
      bartender_scheduled!

      get review_amend_dates_manage_contract_path(contract), params: remove_params

      body = response.body
      expect(body).to include("2 tickets sold (#{number_to_currency(order.total_cents / 100.0)})")
      expect(body).to include("3 comps")
      expect(body).to include("Refund or move them to another date.")
      expect(body).to include(manage_ticket_listing_path(listing))
      expect(body).to include("Ana Ruiz", "Bartender", "1 person scheduled to work.")
      expect(body).to include(manage_staffing_scheduling_path(day: rental.starts_at.to_date.iso8601))
      expect(body).to include("I'll take care of these")
      expect(body).to include('data-controller="acknowledge-gate"')
      expect(body).to match(/data-acknowledge-gate-target="submit"[^>]*disabled/)
    end
  end

  describe "applying the removal" do
    it "refunds nobody and unschedules nobody, then lists what's left on the contract page until it's done" do
      listing = ticketing_on!
      order = paid_order!(listing)
      assignment = bartender_scheduled!

      post apply_amend_dates_manage_contract_path(contract), params: remove_params.merge(acknowledged: "1")

      expect(response).to redirect_to(manage_contract_path(contract))
      expect(SpaceRental.exists?(rental.id)).to be(false)
      expect(order.reload.status).to eq("paid")
      expect(order.tickets.map(&:status).uniq).to eq([ "valid" ])
      expect(ShiftAssignment.exists?(assignment.id)).to be(true)

      get manage_contract_path(contract)
      expect(response.body).to include("Still to do from removed dates")
      expect(response.body).to include("2 tickets to refund or move and 1 person to unschedule.")
      expect(response.body).to include(manage_ticket_listing_path(listing), "Ana Ruiz")

      # Once the person is off the shift, only the tickets are left.
      assignment.destroy!
      get manage_contract_path(contract)
      expect(response.body).to include("2 tickets to refund or move.")
      expect(response.body).not_to include("Ana Ruiz")

      # And once the buyer is refunded, the list is gone.
      # (as TicketOrderRefund leaves it, without calling Stripe)
      order.tickets.update_all(status: "refunded")
      order.update!(status: "refunded", refunded_cents: order.total_cents)
      get manage_contract_path(contract)
      expect(response.body).not_to include("Still to do from removed dates")
    end

    it "keeps no list when the dates left nothing to do" do
      post apply_amend_dates_manage_contract_path(contract), params: remove_params

      expect(contract.reload.draft_data).not_to have_key(ContractDateRemovalImpact::FOLLOW_UP_KEY)
      get manage_contract_path(contract)
      expect(response.body).not_to include("Still to do from removed dates")
    end

    it "can be put away with Done with this list" do
      bartender_scheduled!
      post apply_amend_dates_manage_contract_path(contract), params: remove_params

      delete dismiss_date_removal_follow_up_manage_contract_path(contract)

      expect(response).to redirect_to(manage_contract_path(contract))
      expect(contract.reload.draft_data).not_to have_key(ContractDateRemovalImpact::FOLLOW_UP_KEY)
    end
  end

  describe "Change the deal → review" do
    before { contract.update_amend_data(contract.amend_data.merge("removed_rental_ids" => [ rental.id ])) }

    it "shows the same summary, and records what's left once applied" do
      assignment = bartender_scheduled!

      get amend_review_manage_contract_path(contract)
      expect(response.body).to include("Ana Ruiz", "I'll take care of these")

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "0", acknowledged: "1" }

      expect(SpaceRental.exists?(rental.id)).to be(false)
      expect(ShiftAssignment.exists?(assignment.id)).to be(true)
      get manage_contract_path(contract)
      expect(response.body).to include("Still to do from removed dates", "Ana Ruiz")
    end

    it "says plainly when nothing is affected" do
      get amend_review_manage_contract_path(contract)

      expect(response.body).to include("Nobody is scheduled to work this date.")
      expect(response.body).not_to include("I'll take care of these")
    end
  end

  describe "Cancel contract" do
    it "says plainly when nothing is affected, and lands on the contracts list as before" do
      ticketing_on!

      get cancel_manage_contract_path(contract)
      expect(response.body).to include("No tickets sold and nobody scheduled for this date.")
      expect(response.body).not_to include("I'll take care of these")

      post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all" }

      expect(response).to redirect_to(manage_contracts_path)
      expect(contract.reload.status).to eq("cancelled")
      expect(contract.draft_data).not_to have_key(ContractDateRemovalImpact::FOLLOW_UP_KEY)
    end

    it "lists the tickets and staff behind an acknowledgement, touches neither, and shows what's left on the contract page" do
      listing = ticketing_on!
      order = paid_order!(listing)
      assignment = bartender_scheduled!

      get cancel_manage_contract_path(contract)
      body = response.body
      expect(body).to include("2 tickets sold (#{number_to_currency(order.total_cents / 100.0)})")
      expect(body).to include("Ana Ruiz", "Bartender", manage_ticket_listing_path(listing))
      expect(body).to include("I'll take care of these")
      expect(body).to include("contract-cancel acknowledge-gate")
      expect(body).to match(/data-acknowledge-gate-target="submit"[^>]*disabled/)

      post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all", acknowledged: "1" }

      expect(response).to redirect_to(manage_contract_path(contract))
      expect(contract.reload.status).to eq("cancelled")
      expect(order.reload.status).to eq("paid")
      expect(order.tickets.map(&:status).uniq).to eq([ "valid" ])
      expect(ShiftAssignment.exists?(assignment.id)).to be(true)

      get manage_contract_path(contract)
      expect(response.body).to include("Still to do from removed dates")
      expect(response.body).to include("2 tickets to refund or move and 1 person to unschedule.")
    end

    it "leaves out dates that have already happened" do
      rental.update!(starts_at: 2.weeks.ago.change(hour: 20), ends_at: 2.weeks.ago.change(hour: 23))
      show.update!(date_and_time: 2.weeks.ago.change(hour: 21))
      bartender_scheduled!

      get cancel_manage_contract_path(contract)

      expect(response.body).not_to include("Ana Ruiz")
      expect(response.body).not_to include("I'll take care of these")
    end
  end
end

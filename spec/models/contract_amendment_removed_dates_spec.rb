# frozen_string_literal: true

require "rails_helper"

# Amending a deal to drop a booked date destroys that date's show. The show's
# ShowFinancials after_destroy fires the contract-payment sync mid-destroy —
# after dependent: :nullify has run but before the show's own DELETE, when
# show.destroyed? is still false — and find_payment_for_show writes show_id
# back onto the payment "for future lookups", so the DELETE then hits the
# contract_payments→shows FK. apply_amendment! must unlink payments and
# suppress the sync, same as cancel! and ContractDateChanges.
RSpec.describe Contract, "#apply_amendment! removing booked dates" do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, :revenue_share_per_event, organization: org, production: production) }

  it "drops the date even when a revenue-share payment references its show" do
    starts_at = 3.weeks.from_now.change(hour: 20)
    rental = contract.space_rentals.create!(location: location, starts_at: starts_at,
                                            ends_at: starts_at + 2.hours, confirmed: true)
    show = production.shows.create!(date_and_time: starts_at, duration_minutes: 120,
                                    location: location, space_rental: rental)
    show.create_show_financials!(ticket_revenue: 500, ticket_count: 40)
    payment = contract.contract_payments.create!(description: "Revenue Share", amount: 100,
                                                 direction: "incoming", due_date: starts_at.to_date,
                                                 show_id: show.id)

    expect {
      contract.transaction { contract.apply_amendment!({ "removed_rental_ids" => [ rental.id ] }) }
    }.not_to raise_error

    expect(Show.exists?(show.id)).to be(false)
    expect(SpaceRental.exists?(rental.id)).to be(false)
    expect(payment.reload.show_id).to be_nil
  end

  # The removed ids come from the amend form. Only this contract's own nights
  # go: a foreign id used to take another contract's show (any organization's)
  # with it, and unlink its payments, while only the rental delete was scoped.
  it "never removes another contract's night" do
    other_org = create(:organization, :pro)
    other_location = create(:location, organization: other_org)
    other_production = create(:production, organization: other_org, production_type: "third_party")
    other_contract = create(:contract, :active, :revenue_share_per_event, organization: other_org, production: other_production)
    starts_at = 3.weeks.from_now.change(hour: 20)
    other_rental = other_contract.space_rentals.create!(location: other_location, starts_at: starts_at,
                                                        ends_at: starts_at + 2.hours, confirmed: true)
    other_show = other_production.shows.create!(date_and_time: starts_at, duration_minutes: 120,
                                                location: other_location, space_rental: other_rental)
    other_payment = other_contract.contract_payments.create!(description: "Revenue Share", amount: 100,
                                                             direction: "incoming", due_date: starts_at.to_date,
                                                             show_id: other_show.id)

    contract.transaction { contract.apply_amendment!({ "removed_rental_ids" => [ other_rental.id ] }) }

    expect(Show.exists?(other_show.id)).to be(true)
    expect(SpaceRental.exists?(other_rental.id)).to be(true)
    expect(other_payment.reload.show_id).to eq(other_show.id)
  end

  # Round 9 §0 (2026-10-06): a night people hold tickets for can't be dropped
  # by an amendment; it's canceled in Shows & Events, where they're refunded.
  it "refuses to drop a night that sold tickets" do
    starts_at = 3.weeks.from_now.change(hour: 20)
    rental = contract.space_rentals.create!(location: location, starts_at: starts_at, ends_at: starts_at + 2.hours, confirmed: true)
    show = production.shows.create!(date_and_time: starts_at, duration_minutes: 120, location: location, space_rental: rental)
    listing = TicketListing.create!(show: show, status: "on_sale")
    general = listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_amend")

    expect {
      contract.transaction { contract.apply_amendment!({ "removed_rental_ids" => [ rental.id ] }) }
    }.to raise_error(Contract::TicketsSoldError, /cancel it in Shows & Events first/)
    expect(Show.exists?(show.id)).to be(true)
  end
end

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
end

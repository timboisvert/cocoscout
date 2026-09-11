# frozen_string_literal: true

require "rails_helper"

# A production that comes back year after year keeps its old shows. Contract#
# contract_shows widens to every show in the production when the production has
# a single contract, so this year's contract could see (and link its payments
# to) nights from an earlier run. The positional fallback in
# #link_payments_to_shows then paired this year's payments with those older
# shows purely by order, and once a payment carried that stale link it settled
# from the wrong night's revenue and survived the deletion of its own date:
# ContractDateChanges#drop_pending_payments! matched neither the rental's shows
# nor a null show_id, so the row stayed "due" for a date that no longer existed.
RSpec.describe "stale show links on returning productions" do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) do
    create(:contract, :active, :revenue_share_per_event, organization: org, production: production)
  end

  # Two nights from a run that ended before this contract began, with no rental
  # of their own — exactly the shape that fooled the positional pairing.
  let!(:old_shows) do
    [ 10.months.ago, 8.months.ago ].map do |t|
      production.shows.create!(date_and_time: t.change(hour: 19), duration_minutes: 120, location: location)
    end
  end

  def book!(starts_at)
    rental = contract.space_rentals.create!(location: location, starts_at: starts_at,
                                            ends_at: starts_at + 2.hours, confirmed: true)
    show = production.shows.create!(date_and_time: starts_at, duration_minutes: 120,
                                    location: location, space_rental: rental)
    contract.refresh_dates_from_rentals!
    [ rental, show ]
  end

  describe "Contract#linkable_shows" do
    it "is the contract's own rental nights, not the production's back catalogue" do
      _rental, show = book!(3.weeks.from_now.change(hour: 20))

      expect(contract.contract_shows).to include(*old_shows)
      expect(contract.linkable_shows.to_a).to contain_exactly(show)
    end

    it "falls back to the production's shows for a contract that has booked nothing" do
      expect(contract.space_rentals).to be_empty
      expect(contract.linkable_shows.to_a).to match_array(contract.contract_shows.to_a)
    end
  end

  describe "relinking after an amendment" do
    it "never pairs a payment with a show from an earlier run" do
      first  = 3.weeks.from_now.change(hour: 20)
      second = 4.weeks.from_now.change(hour: 20)
      _r1, show1 = book!(first)
      _r2, show2 = book!(second)

      p1 = contract.contract_payments.create!(description: "Revenue Share", amount: 0, amount_tbd: true,
                                              direction: "outgoing", due_date: first.to_date)
      p2 = contract.contract_payments.create!(description: "Revenue Share", amount: 0, amount_tbd: true,
                                              direction: "outgoing", due_date: second.to_date)

      contract.send(:link_payments_to_shows, [ p1, p2 ], contract.linkable_shows.order(:date_and_time).to_a)

      expect(p1.reload.show_id).to eq(show1.id)
      expect(p2.reload.show_id).to eq(show2.id)
      expect([ p1.show_id, p2.show_id ]).not_to include(*old_shows.map(&:id))
    end

    it "links nothing rather than guessing when the night does not exist yet" do
      rental_only = 3.weeks.from_now.change(hour: 20)
      contract.space_rentals.create!(location: location, starts_at: rental_only,
                                     ends_at: rental_only + 2.hours, confirmed: true)
      contract.refresh_dates_from_rentals!
      payment = contract.contract_payments.create!(description: "Revenue Share", amount: 0, amount_tbd: true,
                                                   direction: "outgoing", due_date: rental_only.to_date)

      contract.send(:link_payments_to_shows, [ payment ], contract.linkable_shows.order(:date_and_time).to_a)

      expect(payment.reload.show_id).to be_nil
    end
  end

  describe "ContractDateChanges.remove!" do
    it "drops a pending payment whose show_id points at an unrelated show" do
      starts_at = 3.weeks.from_now.change(hour: 20)
      rental, _show = book!(starts_at)
      stale = contract.contract_payments.create!(description: "Revenue Share", amount: 0, amount_tbd: true,
                                                 direction: "outgoing", due_date: starts_at.to_date,
                                                 show_id: old_shows.first.id)

      ContractDateChanges.remove!(contract: contract, rental: rental)

      expect(ContractPayment.exists?(stale.id)).to be(false)
    end

    it "leaves another live date's payment alone when the two share a due date" do
      starts_at = 3.weeks.from_now.change(hour: 20)
      rental_a, _show_a = book!(starts_at)
      # A second booking the same night, in its own rental — its money is not
      # the removed date's money even though the due dates match.
      rental_b = contract.space_rentals.create!(location: location, starts_at: starts_at + 3.hours,
                                                ends_at: starts_at + 5.hours, confirmed: true)
      show_b = production.shows.create!(date_and_time: starts_at + 3.hours, duration_minutes: 120,
                                        location: location, space_rental: rental_b)
      keeper = contract.contract_payments.create!(description: "Revenue Share", amount: 0, amount_tbd: true,
                                                  direction: "outgoing", due_date: starts_at.to_date,
                                                  show_id: show_b.id)

      ContractDateChanges.remove!(contract: contract, rental: rental_a)

      expect(ContractPayment.exists?(keeper.id)).to be(true)
      expect(keeper.reload.show_id).to eq(show_b.id)
    end
  end
end

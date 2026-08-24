# frozen_string_literal: true

require "rails_helper"

# Changing dates is its own job. Nothing about the deal is regenerated, which
# is what stops a settled date from sprouting a second payment.
RSpec.describe "Contracts — change dates", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  let(:future) { 3.weeks.from_now.change(hour: 20) }

  def booked_date!(starts_at)
    rental = contract.space_rentals.create!(location: location, starts_at: starts_at,
                                            ends_at: starts_at + 2.hours, confirmed: true)
    show = production.shows.create!(date_and_time: starts_at, duration_minutes: 120,
                                    location: location, space_rental: rental)
    [ rental, show ]
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers the choice between changing dates and changing the deal" do
    get amend_choose_manage_contract_path(contract)

    expect(response.body).to include("Change the dates")
    expect(response.body).to include("Change the deal")
  end

  describe "removing a future date" do
    it "takes the date and its pending payment, and nothing else" do
      rental, show = booked_date!(future)
      _other_rental, = booked_date!(future + 1.week)
      doomed = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                  due_date: future.to_date, show_id: show.id)
      keeper = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                  due_date: (future + 1.week).to_date)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(SpaceRental.exists?(rental.id)).to be(false)
      expect(Show.exists?(show.id)).to be(false)
      expect(ContractPayment.exists?(doomed.id)).to be(false)
      expect(ContractPayment.exists?(keeper.id)).to be(true)
    end
  end

  describe "removing a date that's already been paid" do
    it "cancels it instead of deleting, and leaves the money alone" do
      rental, show = booked_date!(2.weeks.ago.change(hour: 20))
      paid = contract.contract_payments.create!(description: "Settlement", amount: 63, direction: "outgoing",
                                                due_date: rental.starts_at.to_date, show_id: show.id,
                                                status: "paid", paid_date: Date.current)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(Show.find(show.id).canceled).to be(true)
      expect(paid.reload.status).to eq("paid")
      expect(flash[:notice]).to include("already settled")
    end

    # A cancelled date that keeps its booking holds the room against every other
    # event and still reads "Confirmed" on the contract, which is how removing a
    # date looked like it hadn't worked.
    it "still releases the room, and the cancelled show keeps its own times" do
      rental, show = booked_date!(2.weeks.ago.change(hour: 20))
      show.update!(duration_minutes: nil)
      contract.contract_payments.create!(description: "Settlement", amount: 63, direction: "outgoing",
                                         due_date: rental.starts_at.to_date, show_id: show.id,
                                         status: "paid", paid_date: Date.current)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(SpaceRental.exists?(rental.id)).to be(false)
      expect(show.reload.duration_minutes).to eq(120)
      expect(show.ends_at).to eq(show.date_and_time + 120.minutes)
    end
  end

  # A ShowFinancials row gets created just by opening a show's payout page. Read
  # as "settled", it made a future show with no money on it undeletable — the
  # date was merely cancelled and its room stayed booked.
  describe "a future date with an empty financials row" do
    it "deletes it outright, like any other unsettled date" do
      rental, show = booked_date!(future)
      show.create_show_financials!
      pending = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                    due_date: future.to_date, show_id: show.id)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(SpaceRental.exists?(rental.id)).to be(false)
      expect(Show.exists?(show.id)).to be(false)
      expect(ContractPayment.exists?(pending.id)).to be(false)
      expect(flash[:notice]).not_to include("already settled")
    end

    it "but confirmed numbers still count as settled" do
      rental, show = booked_date!(future)
      show.create_show_financials!(ticket_revenue: 400, data_confirmed: true)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(Show.find(show.id).canceled).to be(true)
      expect(flash[:notice]).to include("already settled")
    end
  end

  describe "moving a date" do
    it "keeps the show, so its cast and staffing follow it" do
      rental, show = booked_date!(future)
      performer = create(:person)
      create(:show_person_role_assignment, show: show, assignable: performer)
      payment = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                   due_date: future.to_date, show_id: show.id)
      new_time = future + 2.days

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "move", starts_at: new_time.strftime("%Y-%m-%dT%H:%M") } } }

      expect(show.reload.id).to eq(show.id)
      expect(show.date_and_time.to_date).to eq(new_time.to_date)
      expect(show.show_person_role_assignments.count).to eq(1)
      expect(payment.reload.due_date).to eq(new_time.to_date)
    end
  end

  describe "a date left alone" do
    it "is untouched" do
      rental, show = booked_date!(future)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "keep" } } }

      expect(SpaceRental.exists?(rental.id)).to be(true)
      expect(Show.find(show.id).canceled).to be_falsey
    end
  end

  # The form posts to review first: the plan is shown back, nothing is touched,
  # and confirming re-posts the same params to apply.
  describe "reviewing before applying" do
    it "shows the plan without changing anything" do
      rental, show = booked_date!(future)
      moving, = booked_date!(future + 1.week)
      original_start = moving.starts_at
      pending = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                   due_date: future.to_date, show_id: show.id)
      new_time = future + 3.weeks

      post review_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" },
                              moving.id.to_s => { action: "move", starts_at: new_time.strftime("%Y-%m-%dT%H:%M") } } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dates to Remove")
      expect(response.body).to include("Dates to Move")
      expect(response.body).to include("1 pending payment")

      # Nothing applied yet.
      expect(SpaceRental.exists?(rental.id)).to be(true)
      expect(ContractPayment.exists?(pending.id)).to be(true)
      expect(moving.reload.starts_at).to eq(original_start)

      # Confirming re-posts the same params.
      expect(response.body).to include(%(name="dates[#{rental.id}][action]" value="remove"))
      expect(response.body).to include(%(name="dates[#{moving.id}][starts_at]" value="#{new_time.strftime("%Y-%m-%dT%H:%M")}"))
    end

    it "labels a settled date as a cancellation, not a removal" do
      rental, show = booked_date!(2.weeks.ago.change(hour: 20))
      contract.contract_payments.create!(description: "Settlement", amount: 63, direction: "outgoing",
                                         due_date: rental.starts_at.to_date, show_id: show.id,
                                         status: "paid", paid_date: Date.current)

      post review_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(response.body).to include("Settled Dates to Cancel")
      expect(response.body).not_to include("Dates to Remove")
      expect(Show.find(show.id).canceled).to be_falsey
    end

    it "bounces straight back when nothing would change" do
      rental, = booked_date!(future)

      post review_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "keep" } } }

      expect(response).to redirect_to(amend_dates_manage_contract_path(contract))
      expect(flash[:notice]).to include("No date changes")
    end

    it "treats a move to the same time as no change" do
      rental, = booked_date!(future)

      post review_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "move", starts_at: rental.starts_at.strftime("%Y-%m-%dT%H:%M") } } }

      expect(response).to redirect_to(amend_dates_manage_contract_path(contract))
    end
  end

  describe "cancelling the show itself" do
    it "drops the pending contract payment in the same action" do
      _rental, show = booked_date!(future)
      payment = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                   due_date: future.to_date, show_id: show.id)

      patch manage_cancel_show_path(production, show), params: { scope: "this" }

      expect(show.reload.canceled).to be(true)
      expect(ContractPayment.exists?(payment.id)).to be(false)
      expect(flash[:notice]).to include("pending contract payment")
    end

    it "leaves a paid payment alone" do
      _rental, show = booked_date!(future)
      paid = contract.contract_payments.create!(description: "Rent", amount: 200, direction: "incoming",
                                                due_date: future.to_date, show_id: show.id,
                                                status: "paid", paid_date: Date.current)

      patch manage_cancel_show_path(production, show), params: { scope: "this" }

      expect(paid.reload.status).to eq("paid")
    end
  end
end

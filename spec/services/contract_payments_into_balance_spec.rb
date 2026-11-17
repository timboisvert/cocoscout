# frozen_string_literal: true

require "rails_helper"

# A connected contract's payments can go into the contractor's own
# organization's CocoScout balance, in place of the contractor's bank (Tim,
# 2026-11-17). The contractor chooses. The payment still rides the paying
# organization's one payout run; when the run pays, the money moves from
# one balance to the other, with no bank transfer.
RSpec.describe "Contract payments into the contractor's organization's balance" do
  include ActiveJob::TestHelper

  # The organization that wrote the contract and pays.
  let!(:owner) { create(:user) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:venue) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:location) { create(:location, organization: venue) }
  # The contractor, who runs a Pro organization of their own.
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, name: "Thea Example") }
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
  let!(:payment) do
    create(:contract_payment, contract: contract, show: contract_show, direction: "outgoing", amount: 825.00,
                              due_date: Date.current, description: "Their share")
  end

  before do
    venue.update!(contract_notification_user_ids: [ owner.id ])
    # Money in the paying organization's balance to pay from.
    OrgCashEntry.post!(organization: venue, entry_type: "opening_balance", amount_cents: 500_000, occurred_at: 1.month.ago)
    allow(OrgCashEntry).to receive(:enforcement_enabled?).and_return(true)
    allow(CocoScoutBalance).to receive(:held_cents).and_return(0)
  end

  def choose_balance!
    ContractConnections.set_pay_to!(connection, user: user, balance: true)
  end

  def run_with_payment!
    result = ContractorPayoutRunService.add_contract_payment!(payment, added_by: owner)
    expect(result.error).to be_nil
    result.batch
  end

  describe "the choice" do
    it "is the contractor's, needs Pro, and notifies the paying organization" do
      expect(ContractConnections.pay_target(contract)).to be_nil
      expect { ContractConnections.set_pay_to!(connection, user: owner, balance: true) }.to raise_error(ContractConnections::NotAllowed)

      expect { choose_balance! }.to change(owner.notifications, :count).by(1)
      expect(owner.notifications.last.title).to eq("Your payments to Thea Example for The Holly Problem will go into The Holly Problem's CocoScout balance")
      expect(ContractConnections.pay_target(contract)).to eq(theirs)

      # Off Pro, the next payment goes to the bank again without anyone switching it.
      theirs.update!(comped_indefinitely: false, balance_pooled_at: nil)
      expect(ContractConnections.pay_target(contract.reload)).to be_nil
      expect { ContractConnections.set_pay_to!(connection.reload, user: user, balance: false) }.to change(owner.notifications, :count).by(1)
    end

    it "means My Contracts no longer asks the contractor for a bank" do
      contracts = Contract.where(id: contract.id).includes(:organization)
      paying = ->() { contracts.reload.reject { |c| ContractConnections.pay_target(c) }.map { |c| c.organization.name } }
      expect(paying.call).to eq([ "Stars and Garters" ])
      choose_balance!
      expect(paying.call).to be_empty
    end

    it "stops when the connection ends" do
      choose_balance!
      ContractConnections.unlink!(connection, user: user)
      expect(ContractConnections.pay_target(contract.reload)).to be_nil
    end
  end

  describe "on the payout run" do
    it "goes to the contractor's bank, as a person, until the contractor chooses otherwise" do
      batch = run_with_payment!
      expect(batch.items.sole).to have_attributes(payee: person, amount_cents: 82_500)
      expect(batch.items.sole.partner_organization?).to be(false)
    end

    it "names the contractor's organization as the payee, owed like any payee, and funded by the run" do
      choose_balance!
      batch = run_with_payment!
      item = batch.items.sole

      expect(item).to have_attributes(payee: theirs, amount_cents: 82_500)
      expect(item.partner_organization?).to be(true)
      expect(item.payable_now?).to be(true)
      expect(PayoutBatch.item_state(item)).to eq(:ready)
      expect(venue.payout_balance_cents_for(theirs)).to eq(82_500)
      # Not held money: the run has to fund it.
      expect(item.payout_contributions.sole.held_funds?).to be(false)
      expect(batch.held_cents).to eq(0)
      expect(PayoutRunRemoval.removable?(item.payout_contributions.sole)).to be(true)
    end

    it "moves the money from one balance to the other when the run pays, with no bank transfer" do
      choose_balance!
      batch = run_with_payment!
      batch.update!(status: "funded", funding_status: "succeeded")
      expect(Stripe::Transfer).not_to receive(:create)

      expect { PayoutBatchService.process!(batch) }
        .to change { OrgCashEntry.balance_cents(venue) }.by(-82_500)
        .and change { OrgCashEntry.balance_cents(theirs) }.by(82_500)

      item = batch.items.sole.reload
      expect(item).to have_attributes(status: "paid", stripe_transfer_id: nil)
      expect(item.deposited_at).to be_present
      expect(batch.reload.status).to eq("completed")
      expect(payment.reload).to be_status_paid
      expect(venue.payout_balance_cents_for(theirs)).to eq(0)
      expect(OrgCashEntry.find_by!(organization: theirs, entry_type: "partner_payment_in")).to have_attributes(amount_cents: 82_500, source: item)
      expect(CocoScoutBalance.sources(theirs)[:contracts]).to eq(82_500)
      # Nobody is counted as a person paid for it.
      expect(UsageRules.paid(Date.current, organization: venue, staff: false)).to eq({})
    end

    it "notifies the people who run the receiving organization" do
      choose_balance!
      batch = run_with_payment!
      batch.update!(status: "funded", funding_status: "succeeded")

      expect { PayoutBatchService.process!(batch) }.to change { user.notifications.where(kind: "contract_share_paid_into_balance").count }.by(1)
      notice = user.notifications.where(kind: "contract_share_paid_into_balance").last
      expect(notice.title).to eq("Stars and Garters paid $825.00 into The Holly Problem's balance")
      # It opens where the money is, and the payer's own ledger line reads properly.
      expect(notice.path).to eq("/manage/money/books/balance")
      expect(OrgCashEntry.where(organization: venue, entry_type: "transfer").last.description).to end_with("paid into The Holly Problem's CocoScout balance")
    end

    it "writes a name that ends in s the right way in the payer's ledger" do
      theirs.update!(name: "Thea Presents")
      choose_balance!
      batch = run_with_payment!
      batch.update!(status: "funded", funding_status: "succeeded")
      PayoutBatchService.process!(batch)

      expect(OrgCashEntry.where(organization: venue, entry_type: "transfer").last.description).to end_with("paid into Thea Presents' CocoScout balance")
    end

    it "posts it in both organizations' books: paid from one balance, contract income in the other, by production and date" do
      choose_balance!
      followed = their_production.shows.find_by!(linked_show: contract_show)
      batch = run_with_payment!
      batch.update!(status: "funded", funding_status: "succeeded")
      perform_enqueued_jobs { PayoutBatchService.process!(batch) }

      lines = ->(organization, key) { JournalLine.joins(:journal_entry, :ledger_account).where(journal_entries: { organization_id: organization.id }, ledger_accounts: { key: key }) }
      # The receiving organization: money in its balance, earned as contract income for its own production and date.
      income = lines.call(theirs, "contract_income")
      expect(income.sum(:amount_cents)).to eq(-82_500)
      expect(income.pluck(:production_id, :show_id)).to eq([ [ their_production.id, followed.id ] ])
      expect(lines.call(theirs, "cocoscout_balance").sum(:amount_cents)).to eq(82_500)

      # The paying organization: owed when it went on the run, cleared when the run paid, out of its balance.
      expect(lines.call(venue, "owed_to_payees").sum(:amount_cents)).to eq(0)
      expect(lines.call(venue, "contractor_pay").sum(:amount_cents)).to eq(82_500)
    end

    it "leaves a payment already on a run where it was going when the choice changes" do
      batch = run_with_payment!
      choose_balance!
      expect(batch.items.sole.payee).to eq(person)
    end

    it "fails the line, and nothing else, if the receiving organization has left Pro by the time the run pays" do
      choose_balance!
      batch = run_with_payment!
      batch.update!(status: "funded", funding_status: "succeeded")
      theirs.update!(comped_indefinitely: false, balance_pooled_at: nil)

      expect { PayoutBatchService.process!(batch) }.not_to change { OrgCashEntry.balance_cents(theirs) }
      expect(batch.items.sole.reload).to have_attributes(status: "failed")
      expect(OrgCashEntry.balance_cents(venue)).to eq(500_000)
    end
  end
end

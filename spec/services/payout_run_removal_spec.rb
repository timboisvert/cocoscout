# frozen_string_literal: true

require "rails_helper"

# Taking one thing back out of a draft payout run, the same way whatever it
# is (Tim, 2026-10-11: Pavlov's $240 share went in, another ticket sold, and
# nothing could come back out).
RSpec.describe PayoutRunRemoval do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }

  describe "a contract payment" do
    let(:organization) { org }
    let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: org) }
    let(:production) { create(:production, organization: org, production_type: "third_party").tap { |p| contract.update!(production: p) } }
    let(:show) { create(:show, production: production, date_and_time: 2.days.ago.change(hour: 19)) }
    let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }
    let!(:share) do
      create(:contract_payment, :revenue_share_tbd, contract: contract, direction: "outgoing", due_date: show.date_and_time.to_date + 1)
    end

    before do
      contract.update!(contractor: create(:contractor, organization: org, name: "Pavlov",
                                                       person: create(:person, stripe_account_id: "acct_pav", payouts_enabled: true)))
    end

    def sell(count, intent)
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
      TicketOrderSettlement.settle!(order, payment_intent_id: intent)
    end

    it "comes out with its netted charge, catches up with sales since, and can go back in" do
      travel_to show.date_and_time - 1.day do
        sell(2, "pi_1") # $40, 20% to them
      end
      booth = create(:contract_payment, contract: contract, direction: "incoming", amount: 2, description: "Booth Tech",
                                        settlement_method: "payout_deduction", due_date: show.date_and_time.to_date)
      expect(share.reload.amount).to eq(8.to_d)
      ContractorPayoutRunService.add_contract_payment!(share)
      expect(booth.reload).to be_status_paid
      batch = PayoutBatch.current_open_draft(org)
      expect(batch.total_cents).to eq(600)

      travel_to show.date_and_time - 2.hours do
        sell(1, "pi_2") # another $20 after it went in
      end
      expect(share.reload.amount).to eq(8.to_d) # a payment in a run is never rewritten

      result = described_class.remove!(share.payout_contribution)
      expect(result.error).to be_nil
      expect(result.notice).to include("it's now $12.00")
      expect(share.reload).not_to be_in_payout_run
      expect(share.amount).to eq(12.to_d)
      expect(booth.reload).to be_status_pending
      expect(batch.reload.total_cents).to eq(0)
      expect(PayoutLedgerEntry.where(payee: contract.contractor.person).sum(:amount_cents)).to eq(0)

      ContractorPayoutRunService.add_contract_payment!(share)
      expect(PayoutBatch.current_open_draft(org).total_cents).to eq(1_000) # $12 less the $2 booth tech
    end

    it "won't come out of a run that's been sent" do
      travel_to(show.date_and_time - 1.day) { sell(2, "pi_1") }
      ContractorPayoutRunService.add_contract_payment!(share.reload)
      PayoutBatch.current_open_draft(org).update_columns(status: "funding")

      expect(described_class.remove!(share.payout_contribution).error).to include("Only something in a draft run")
      expect(share.reload).to be_in_payout_run
    end
  end

  describe "a show payout and staff pay on the same run" do
    let(:person) { create(:person, name: "Dual Dana", stripe_account_id: "acct_dual", payouts_enabled: true) }
    let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }
    let(:production) { create(:production, organization: org) }

    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    def staff_pay!
      StaffPayRunService.add_lines!(organization: org, created_by: owner,
                                    lines: [ { staff_member: member, hours: 5, bonus_cents: 1_500,
                                               reimbursement_cents: 0, tips_cents: 0 } ]).batch
    end

    def show_pay!
      show = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)
      payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 200)
      line = ShowPayoutLineItem.create!(show_payout: payout, payee: person, amount: 200)
      PerformerPayoutRunService.add_show_payout!(payout)
      line
    end

    it "takes the show payout out alone: still owed, staff pay untouched" do
      batch = staff_pay!
      line = show_pay!
      item = batch.reload.items.sole
      expect(item.amount_cents).to eq(31_500)

      result = described_class.remove!(line.payout_contribution)
      expect(result.notice).to include("still owed")
      expect(item.reload.amount_cents).to eq(11_500)
      expect(org.payout_balance_cents_for(person, category: "performer")).to eq(20_000)
    end

    it "takes a person's staff pay out whole, back into Pay People, leaving the show payout" do
      batch = staff_pay!
      show_pay!
      item = batch.reload.items.sole
      staff_line = item.payout_contributions.find { |c| c.category == "staffing" }

      result = described_class.remove!(staff_line)
      expect(result.notice).to include("back in Pay People")
      expect(item.reload.payout_contributions.map(&:category)).to eq([ "performer" ])
      expect(item.amount_cents).to eq(20_000)
      expect(org.payout_balance_cents_for(person, category: "staffing")).to eq(0)
      draft = JSON.parse(PayDraft.read(org))
      expect(draft["lines"][member.id.to_s]).to include("bonus" => "15.00")
    end
  end
end

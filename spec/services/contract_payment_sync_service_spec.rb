# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractPaymentSyncService, type: :service do
  let(:organization) { create(:organization) }

  describe "#call" do
    context "when production is not third-party" do
      let(:production) { create(:production, organization: organization) }
      let(:show) { create(:show, production: production, date_and_time: 1.week.ago) }

      it "does nothing" do
        service = described_class.new(show)
        expect { service.call }.not_to raise_error
      end
    end

    context "when contract is not revenue share" do
      let(:contract) { create(:contract, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }
      let(:show) { create(:show, production: production, date_and_time: 1.week.ago) }

      it "does nothing" do
        payment = create(:contract_payment, contract: contract, due_date: 1.week.ago)
        service = described_class.new(show)
        expect { service.call }.not_to change { payment.reload.amount }
      end
    end

    context "with per_event settlement" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }

      it "updates the matching payment with contractor share" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, other_revenue: 0.0)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 16))

        described_class.new(show).call

        payment.reload
        # Contract is 80/20 split, contractor gets 20%
        expect(payment.amount).to eq(200.0)
        expect(payment.amount_tbd).to be false
      end

      it "never overwrites a payment that's already been paid" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, other_revenue: 0.0)
        # A settled payment — a re-sync (e.g. a contractor re-reporting sales on a
        # closed contract) must not rewrite money that already moved.
        payment = create(:contract_payment, :paid, contract: contract, due_date: Date.new(2026, 3, 16), amount: 999.0)

        expect { described_class.new(show).call }.not_to change { payment.reload.amount }
        expect(payment.amount).to eq(999.0)
      end

      it "includes other revenue in the calculation" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        create(:show_financials, :complete, show: show, ticket_revenue: 800.0, other_revenue: 200.0)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 16))

        described_class.new(show).call

        payment.reload
        # Total revenue = 1000, contractor gets 20% = 200
        expect(payment.amount).to eq(200.0)
      end

      it "keeps TBD when show has no real financial data" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).middle_of_day)
        # Show with no real financial data - no financials record
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract,
                         due_date: Date.new(2026, 3, 16))

        described_class.new(show).call

        payment.reload
        expect(payment.amount).to eq(0)
        expect(payment.amount_tbd).to be true
      end

      it "populates notes with show details" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).middle_of_day)
        create(:show_financials, :complete, show: show, ticket_revenue: 500.0)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 16))

        described_class.new(show).call

        payment.reload
        expect(payment.notes).to include("Auto-calculated from show financials")
        expect(payment.notes).to include("$500.00")
      end
    end

    context "with monthly settlement" do
      let(:contract) { create(:contract, :revenue_share, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }

      it "aggregates all shows in the same month" do
        show1 = create(:show, production: production, date_and_time: Date.new(2026, 3, 7).to_time)
        create(:show_financials, :complete, show: show1, ticket_revenue: 600.0)

        show2 = create(:show, production: production, date_and_time: Date.new(2026, 3, 21).to_time)
        create(:show_financials, :complete, show: show2, ticket_revenue: 400.0)

        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        # Trigger sync from either show
        described_class.new(show1).call

        payment.reload
        # Total revenue = 1000, contractor gets 30% = 300
        expect(payment.amount).to eq(300.0)
        expect(payment.amount_tbd).to be false
      end

      it "leaves amount_tbd true when some shows have no financials" do
        show1 = create(:show, production: production, date_and_time: Date.new(2026, 3, 7).middle_of_day)
        create(:show_financials, :complete, show: show1, ticket_revenue: 600.0)

        # Second show has NO financials record at all
        create(:show, production: production, date_and_time: Date.new(2026, 3, 21).middle_of_day)

        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        described_class.new(show1).call

        payment.reload
        # Only show1 confirmed: 600 * 30% = 180
        expect(payment.amount).to eq(180.0)
        expect(payment.amount_tbd).to be true # still pending shows
      end

      it "includes pending count in notes" do
        show1 = create(:show, production: production, date_and_time: Date.new(2026, 3, 7).middle_of_day)
        create(:show_financials, :complete, show: show1, ticket_revenue: 600.0)

        # Second show has NO financials record
        create(:show, production: production, date_and_time: Date.new(2026, 3, 21).middle_of_day)

        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        described_class.new(show1).call

        payment.reload
        expect(payment.notes).to include("1 show(s) still pending")
      end

      it "does not touch payments in other months" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        create(:show_financials, :complete, show: show, ticket_revenue: 500.0)

        march_payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))
        april_payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 4, 30))

        described_class.new(show).call

        march_payment.reload
        april_payment.reload

        expect(march_payment.amount).to eq(150.0) # 500 * 30%
        expect(april_payment.amount).to eq(0) # no shows in April
        expect(april_payment.amount_tbd).to be true
      end
    end

    context "with weekly settlement" do
      let(:contract) { create(:contract, :revenue_share_weekly, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }

      it "aggregates shows within the same week" do
        # Monday March 9, 2026
        monday = Date.new(2026, 3, 9)

        show1 = create(:show, production: production, date_and_time: (monday + 1.day).to_time) # Tuesday
        create(:show_financials, :complete, show: show1, ticket_revenue: 300.0)

        show2 = create(:show, production: production, date_and_time: (monday + 3.days).to_time) # Thursday
        create(:show_financials, :complete, show: show2, ticket_revenue: 200.0)

        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: monday + 5.days) # Saturday

        described_class.new(show1).call

        payment.reload
        # Total = 500, contractor gets 40% = 200
        expect(payment.amount).to eq(200.0)
        expect(payment.amount_tbd).to be false
      end
    end

    context "with flat fee show financials" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }

      it "uses flat fee as revenue" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        create(:show_financials, :complete, :flat_fee, show: show, flat_fee: 2000.0)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 16))

        described_class.new(show).call

        payment.reload
        # 2000 * 20% = 400
        expect(payment.amount).to eq(400.0)
      end
    end

    context "with no matching payment" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }

      it "does not raise an error" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: show, ticket_revenue: 500.0)
        # No contract payments exist

        expect { described_class.new(show).call }.not_to raise_error
      end
    end

    context "with production that has no contract" do
      let(:production) { create(:production, organization: organization, production_type: "third_party") }

      it "does nothing" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        expect { described_class.new(show).call }.not_to raise_error
      end
    end

    context "Case 3 — revenue minus a flat fee (we sell, we pay them the rest)" do
      let(:contract) do
        create(:contract, :active, organization: organization, draft_data: {
                 "payment_structure" => "flat_fee",
                 "payment_config" => { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 300 }
               })
      end
      let(:production) do
        create(:production, organization: organization, production_type: "third_party")
              .tap { |p| contract.update!(production: p) }
      end

      it "settles the outgoing payment to ticket revenue minus the fee" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, other_revenue: 0.0)
        payment = create(:contract_payment, contract: contract, direction: "outgoing",
                                            amount: 0, amount_tbd: true, due_date: 1.week.ago)

        described_class.new(show).call

        payment.reload
        expect(payment.amount).to eq(700.0) # 1000 revenue − 300 fee
        expect(payment.amount_tbd).to be false
      end
    end

    context "Case 3 when a night sells for less than our fee" do
      # We sell the tickets and keep a $300 fee. The night took $190, so there's
      # nothing to hand back — the same settlement now faces the other way and
      # they owe us the $110 our fee wasn't covered by. One payment per show.
      let(:contract) do
        create(:contract, :active, organization: organization, draft_data: {
                 "payment_structure" => "flat_fee",
                 "payment_config" => {
                   "flat_fee_direction" => "ticket_revenue_minus_fee",
                   "flat_fee_amount" => 300,
                   "flat_fee_basis" => "per_show",
                   "flat_fee_settlement" => "per_event"
                 }
               })
      end
      let(:production) do
        create(:production, organization: organization, production_type: "third_party")
              .tap { |p| contract.update!(production: p) }
      end
      let(:show) { create(:show, production: production, date_and_time: Date.new(2026, 8, 15).to_time) }
      let!(:settlement) do
        create(:contract_payment, contract: contract, direction: "outgoing", show: show,
                                  description: "Ticket revenue less $300.00 fee",
                                  amount: 0, amount_tbd: true, due_date: Date.new(2026, 8, 15))
      end

      it "turns the settlement around to bill them the part their tickets didn't cover" do
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)

        described_class.new(show).call

        expect(settlement.reload).to have_attributes(
          direction: "incoming", amount: 110.0, amount_tbd: false, auto_shortfall: true,
          status: "pending", show_id: show.id, description: "Fee shortfall — Aug 15"
        )
        expect(contract.contract_payments.count).to eq(1)
      end

      it "leaves the turned-around settlement collectable rather than waiting on a payout to net it" do
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)

        described_class.new(show).call

        expect(settlement.reload.deduct_from_payout?).to be false
        expect(settlement.collectable_online?).to be true
        expect(contract.outgoing_settlement?).to be false
      end

      it "restates what they owe when the reported revenue changes" do
        financials = create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)
        described_class.new(show).call

        financials.update!(ticket_revenue: 250.0)
        described_class.new(show.reload).call

        expect(settlement.reload).to have_attributes(direction: "incoming", amount: 50.0)
      end

      it "faces them again once the night covers the fee" do
        financials = create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)
        described_class.new(show).call
        expect(settlement.reload).to be_direction_incoming

        financials.update!(ticket_revenue: 500.0)
        described_class.new(show.reload).call

        expect(settlement.reload).to have_attributes(
          direction: "outgoing", amount: 200.0, auto_shortfall: false, # 500 revenue − 300 fee
          description: "Ticket revenue less $300.00 fee — Aug 15"
        )
      end

      it "settles to nothing, not late, when the night covers the fee exactly" do
        create(:show_financials, :complete, show: show, ticket_revenue: 300.0, other_revenue: 0.0)

        described_class.new(show).call

        expect(settlement.reload).to have_attributes(direction: "outgoing", amount: 0.0, amount_tbd: false)
        expect(settlement.nothing_to_hand_back?).to be true
        expect(settlement.overdue?).to be false
      end

      it "goes back to TBD facing them if the financials are withdrawn" do
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)
        described_class.new(show).call
        expect(settlement.reload).to be_direction_incoming

        show.show_financials.destroy!
        described_class.new(show.reload).call

        expect(settlement.reload).to have_attributes(direction: "outgoing", amount: 0.0, amount_tbd: true, auto_shortfall: false)
      end

      it "leaves a settlement that already went through alone" do
        # Whatever a paid settlement settled for, it settled — restating the
        # revenue behind it must not turn it into a bill.
        settlement.update!(status: "paid", paid_date: Date.current, amount: 400.0, amount_tbd: false)
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)

        described_class.new(show).call

        expect(settlement.reload).to have_attributes(direction: "outgoing", amount: 400.0, status: "paid")
        expect(contract.contract_payments.count).to eq(1)
      end

      it "leaves a settlement that's already on a payout run alone" do
        settlement.update!(amount: 400.0, amount_tbd: false)
        payee = create(:person)
        batch = PayoutBatch.create!(organization: organization, status: "draft", kind: "performer")
        item = batch.items.create!(payee: payee, amount_cents: 40_000)
        batch.payout_contributions.create!(source: settlement, payout_batch_item: item,
                                           payee: payee, amount_cents: 40_000, label: "Settlement")
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)

        described_class.new(show).call

        expect(settlement.reload).to have_attributes(direction: "outgoing", amount: 400.0)
      end

      it "counts the shortfall as money in, so the fee lands whole in the books" do
        create(:show_financials, :complete, show: show, ticket_revenue: 190.0, other_revenue: 0.0)
        described_class.new(show).call

        summary = contract.reload.money_summary
        # $190 of tickets we're holding plus the $110 they owe = our $300 fee.
        expect(summary[:money_in]).to eq(300.0)
        expect(summary[:money_out]).to eq(0.0)
      end
    end

    context "Case 3 settling weekly on a per-show fee" do
      # Six shows, three a week, $250 a show. We sell; each week we hand back
      # that week's ticket revenue less $750.
      let(:contract) do
        create(:contract, :active, organization: organization, draft_data: {
                 "payment_structure" => "flat_fee",
                 "payment_config" => {
                   "flat_fee_direction" => "ticket_revenue_minus_fee",
                   "flat_fee_amount" => 250,
                   "flat_fee_basis" => "per_show",
                   "flat_fee_settlement" => "weekly"
                 }
               })
      end
      let(:production) do
        create(:production, organization: organization, production_type: "third_party")
              .tap { |p| contract.update!(production: p) }
      end

      # Week of Mon Mar 2, then week of Mon Mar 9.
      let(:week_one_dates) { [ Date.new(2026, 3, 3), Date.new(2026, 3, 5), Date.new(2026, 3, 7) ] }
      let(:week_two_dates) { [ Date.new(2026, 3, 10), Date.new(2026, 3, 12), Date.new(2026, 3, 14) ] }

      def show_on(date, revenue)
        create(:show, production: production, date_and_time: date.to_time(:utc).change(hour: 20)).tap do |show|
          create(:show_financials, :complete, show: show, ticket_revenue: revenue, other_revenue: 0.0)
        end
      end

      it "deducts only that week's shows from that week's settlement" do
        week_one = create(:contract_payment, contract: contract, direction: "outgoing",
                                             description: "Ticket revenue less $750.00 fee — week of Mar 2",
                                             amount: 0, amount_tbd: true, due_date: Date.new(2026, 3, 7))
        week_two = create(:contract_payment, contract: contract, direction: "outgoing",
                                             description: "Ticket revenue less $750.00 fee — week of Mar 9",
                                             amount: 0, amount_tbd: true, due_date: Date.new(2026, 3, 14))

        week_one_dates.each { |d| show_on(d, 1000.0) }
        week_two_dates.each { |d| show_on(d, 400.0) }

        described_class.new(production.shows.order(:date_and_time).last).call

        expect(week_one.reload.amount).to eq(2250.0) # 3000 revenue − 3 × 250
        expect(week_one.amount_tbd).to be false
        expect(week_two.reload.amount).to eq(450.0)  # 1200 revenue − 3 × 250
        expect(week_two.amount_tbd).to be false
      end

      it "turns a week that sold under its fee around so they owe us the difference" do
        payment = create(:contract_payment, contract: contract, direction: "outgoing",
                                            description: "Ticket revenue less $750.00 fee — week of Mar 2",
                                            amount: 0, amount_tbd: true, due_date: Date.new(2026, 3, 7))

        week_one_dates.each { |d| show_on(d, 100.0) }

        described_class.new(production.shows.first).call

        # 300 revenue − 750 fee: nothing to hand back, $450 of fee uncovered.
        expect(payment.reload).to have_attributes(direction: "incoming", amount: 450.0, auto_shortfall: true,
                                                  description: "Fee shortfall — Mar 3–Mar 7")
      end

      it "holds a week at TBD until every show in it is confirmed" do
        payment = create(:contract_payment, contract: contract, direction: "outgoing",
                                            description: "Ticket revenue less $750.00 fee — week of Mar 2",
                                            amount: 0, amount_tbd: true, due_date: Date.new(2026, 3, 7))

        show_on(week_one_dates.first, 1000.0)
        # The other two dates exist but have no financials yet.
        week_one_dates.drop(1).each do |d|
          create(:show, production: production, date_and_time: d.to_time(:utc).change(hour: 20))
        end

        described_class.new(production.shows.first).call

        payment.reload
        expect(payment.amount).to eq(750.0) # 1000 revenue − 1 × 250
        expect(payment.amount_tbd).to be true
      end
    end

    context "Case 3 on a whole-run fee settled weekly" do
      # The same deal written as one $1,500 total rather than $250 a show: the
      # fee is spread across the six dates, so each week still deducts $750.
      let(:contract) do
        create(:contract, :active, organization: organization, draft_data: {
                 "payment_structure" => "flat_fee",
                 "payment_config" => {
                   "flat_fee_direction" => "ticket_revenue_minus_fee",
                   "flat_fee_amount" => 1500,
                   "flat_fee_basis" => "contract",
                   "flat_fee_settlement" => "weekly"
                 }
               })
      end
      let(:production) do
        create(:production, organization: organization, production_type: "third_party")
              .tap { |p| contract.update!(production: p) }
      end

      it "spreads the total across the run" do
        payment = create(:contract_payment, contract: contract, direction: "outgoing",
                                            description: "Ticket revenue less $750.00 fee — week of Mar 2",
                                            amount: 0, amount_tbd: true, due_date: Date.new(2026, 3, 7))

        [ Date.new(2026, 3, 3), Date.new(2026, 3, 5), Date.new(2026, 3, 7) ].each do |date|
          show = create(:show, production: production, date_and_time: date.to_time(:utc).change(hour: 20))
          create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, other_revenue: 0.0)
        end
        # Three more dates the following week, unreported.
        [ Date.new(2026, 3, 10), Date.new(2026, 3, 12), Date.new(2026, 3, 14) ].each do |date|
          create(:show, production: production, date_and_time: date.to_time(:utc).change(hour: 20))
        end

        described_class.new(production.shows.order(:date_and_time).first).call

        # 3 of 6 shows → half the $1,500 total.
        expect(payment.reload.amount).to eq(2250.0)
      end
    end
  end
end

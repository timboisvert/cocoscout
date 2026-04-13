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
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }
      let(:show) { create(:show, production: production, date_and_time: 1.week.ago) }

      it "does nothing" do
        payment = create(:contract_payment, contract: contract, due_date: 1.week.ago)
        service = described_class.new(show)
        expect { service.call }.not_to change { payment.reload.amount }
      end
    end

    context "with per_event settlement" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

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
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

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
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

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
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

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
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

      it "does not raise an error" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: show, ticket_revenue: 500.0)
        # No contract payments exist

        expect { described_class.new(show).call }.not_to raise_error
      end
    end

    context "with production that has no contract" do
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: nil) }

      it "does nothing" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        expect { described_class.new(show).call }.not_to raise_error
      end
    end
  end
end

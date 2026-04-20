# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract, "revenue share methods", type: :model do
  let(:organization) { create(:organization) }

  describe "#revenue_share?" do
    it "returns true for revenue_share payment structure" do
      contract = create(:contract, :revenue_share, organization: organization)
      expect(contract.revenue_share?).to be true
    end

    it "returns false for flat_fee payment structure" do
      contract = create(:contract, organization: organization, draft_data: { "payment_structure" => "flat_fee" })
      expect(contract.revenue_share?).to be false
    end

    it "returns false when no payment structure set" do
      contract = create(:contract, organization: organization)
      expect(contract.revenue_share?).to be false
    end
  end

  describe "#revenue_share_percentage" do
    it "returns the org's share percentage" do
      contract = create(:contract, :revenue_share, organization: organization)
      expect(contract.revenue_share_percentage).to eq(70.0)
    end

    it "returns nil for non-revenue-share contracts" do
      contract = create(:contract, organization: organization)
      expect(contract.revenue_share_percentage).to be_nil
    end
  end

  describe "#contractor_share_percentage" do
    it "returns 100 minus the org share" do
      contract = create(:contract, :revenue_share, organization: organization)
      expect(contract.contractor_share_percentage).to eq(30.0)
    end

    it "returns nil for non-revenue-share contracts" do
      contract = create(:contract, organization: organization)
      expect(contract.contractor_share_percentage).to be_nil
    end

    it "handles non-standard splits" do
      contract = create(:contract, organization: organization, draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => { "revenue_our_share" => 55 }
      })
      expect(contract.contractor_share_percentage).to eq(45.0)
    end
  end

  describe "#revenue_share_summary" do
    let(:contract) { create(:contract, :revenue_share, :active, organization: organization) }
    let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

    context "with no shows" do
      it "returns summary with zero values" do
        production # ensure production exists
        summary = contract.revenue_share_summary
        expect(summary[:confirmed_revenue]).to eq(0)
        expect(summary[:confirmed_count]).to eq(0)
        expect(summary[:pending_count]).to eq(0)
        expect(summary[:our_share]).to eq(0)
        expect(summary[:contractor_share]).to eq(0)
      end
    end

    context "with confirmed show financials" do
      before do
        show1 = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: show1, ticket_revenue: 1000.0, other_revenue: 0.0)

        show2 = create(:show, production: production, date_and_time: 2.weeks.ago)
        create(:show_financials, :complete, show: show2, ticket_revenue: 500.0, other_revenue: 100.0)
      end

      it "calculates total confirmed revenue" do
        summary = contract.revenue_share_summary
        expect(summary[:confirmed_revenue]).to eq(1600.0)
      end

      it "counts confirmed shows" do
        summary = contract.revenue_share_summary
        expect(summary[:confirmed_count]).to eq(2)
      end

      it "calculates the org share (70%)" do
        summary = contract.revenue_share_summary
        expect(summary[:our_share]).to eq(1120.0) # 1600 * 0.70
      end

      it "calculates the contractor share (30%)" do
        summary = contract.revenue_share_summary
        expect(summary[:contractor_share]).to eq(480.0) # 1600 * 0.30
      end

      it "reports zero pending" do
        summary = contract.revenue_share_summary
        expect(summary[:pending_count]).to eq(0)
      end
    end

    context "with a mix of confirmed and pending shows" do
      before do
        confirmed_show = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: confirmed_show, ticket_revenue: 800.0)

        # Pending show with NO financials record at all
        create(:show, production: production, date_and_time: 2.weeks.ago)
      end

      it "only sums confirmed show revenue" do
        summary = contract.revenue_share_summary
        expect(summary[:confirmed_revenue]).to eq(800.0)
      end

      it "counts pending shows separately" do
        summary = contract.revenue_share_summary
        expect(summary[:confirmed_count]).to eq(1)
        expect(summary[:pending_count]).to eq(1)
      end

      it "only calculates shares on confirmed revenue" do
        summary = contract.revenue_share_summary
        expect(summary[:our_share]).to eq(560.0)     # 800 * 0.70
        expect(summary[:contractor_share]).to eq(240.0) # 800 * 0.30
      end
    end

    context "with shows that have no financials record" do
      before do
        create(:show, production: production, date_and_time: 1.week.ago)
        # No show_financials created
      end

      it "counts them as pending" do
        summary = contract.revenue_share_summary
        expect(summary[:pending_count]).to eq(1)
        expect(summary[:confirmed_count]).to eq(0)
      end
    end

    it "returns nil for non-revenue-share contracts" do
      flat_contract = create(:contract, :active, organization: organization)
      expect(flat_contract.revenue_share_summary).to be_nil
    end
  end

  describe "#find_payment_for_show" do
    context "with monthly settlement" do
      let(:contract) { create(:contract, :revenue_share, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

      it "matches a show to a payment in the same month" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        expect(contract.find_payment_for_show(show)).to eq(payment)
      end

      it "does not match a show to a payment in a different month" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        payment_april = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 4, 30))
        payment_march = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        expect(contract.find_payment_for_show(show)).to eq(payment_march)
      end

      it "returns nil when no exact month match" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 4, 15))

        expect(contract.find_payment_for_show(show)).to be_nil
      end
    end

    context "with weekly settlement" do
      let(:contract) { create(:contract, :revenue_share_weekly, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

      it "matches a show to a payment in the same week" do
        # Monday March 9, 2026
        monday = Date.new(2026, 3, 9)
        show = create(:show, production: production, date_and_time: (monday + 2.days).to_time) # Wednesday
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: monday + 4.days) # Friday same week

        expect(contract.find_payment_for_show(show)).to eq(payment)
      end
    end

    context "with per_event settlement" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
      let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

      it "matches to the closest payment by date" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 15).to_time)
        far_payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 4, 15))
        close_payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 16))

        expect(contract.find_payment_for_show(show)).to eq(close_payment)
      end
    end

    it "returns nil for non-revenue-share contracts" do
      contract = create(:contract, :active, organization: organization)
      production = create(:production, organization: organization, contract: contract)
      show = create(:show, production: production, date_and_time: 1.week.ago)

      expect(contract.find_payment_for_show(show)).to be_nil
    end
  end

  describe "#shows_for_payment" do
    let(:contract) { create(:contract, :revenue_share, :active, organization: organization) }
    let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }

    context "with monthly settlement" do
      it "returns all shows in the payment's month" do
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 31))

        march_show1 = create(:show, production: production, date_and_time: Date.new(2026, 3, 7).to_time)
        march_show2 = create(:show, production: production, date_and_time: Date.new(2026, 3, 21).to_time)
        april_show = create(:show, production: production, date_and_time: Date.new(2026, 4, 5).to_time)

        result = contract.shows_for_payment(payment)
        expect(result).to contain_exactly(march_show1, march_show2)
        expect(result).not_to include(april_show)
      end
    end

    context "with per_event settlement" do
      let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }

      it "returns the show at the same position (1:1 pairing by date order)" do
        payment1 = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 2))
        payment2 = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 15))

        first_show = create(:show, production: production, date_and_time: Date.new(2026, 3, 1).to_time)
        second_show = create(:show, production: production, date_and_time: Date.new(2026, 3, 14).to_time)

        expect(contract.shows_for_payment(payment1)).to eq([ first_show ])
        expect(contract.shows_for_payment(payment2)).to eq([ second_show ])
      end

      it "uses direct show_id link when set" do
        show = create(:show, production: production, date_and_time: Date.new(2026, 3, 14).to_time)
        payment = create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: Date.new(2026, 3, 15), show: show)

        expect(contract.shows_for_payment(payment)).to eq([ show ])
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contractor payout line item creation" do
  let(:organization) { create(:organization) }
  let(:contractor) { create(:contractor, organization: organization, venmo_identifier: "danvenmo") }
  let(:contract) { create(:contract, :active, :revenue_share, :with_contractor, organization: organization, contractor: contractor) }
  let(:production) { create(:production, organization: organization, production_type: "third_party", contract: contract) }
  let(:show) { create(:show, production: production, date_and_time: 1.day.ago) }
  let!(:show_financials) { create(:show_financials, show: show, ticket_revenue: 1000, ticket_count: 50, data_confirmed: true) }
  let!(:show_payout) { create(:show_payout, show: show) }

  # The contract has 70/30 split (revenue_our_share=70), so contractor gets 30%
  let(:expected_contractor_amount) { 300.00 }

  describe "creating contractor line item" do
    it "creates a line item with the correct contractor share" do
      line_item = show_payout.line_items.find_or_initialize_by(
        payee_type: "Contractor",
        payee_id: contractor.id
      )
      total_revenue = show_financials.total_revenue
      contractor_pct = contract.contractor_share_percentage
      contractor_amount = (total_revenue * contractor_pct / 100.0).round(2)

      line_item.update!(amount: contractor_amount)

      expect(line_item.amount).to eq(expected_contractor_amount)
      expect(line_item.payee).to eq(contractor)
      expect(line_item.payee_name).to eq(contractor.name)
    end

    it "supports polymorphic Contractor as payee" do
      line_item = create(:show_payout_line_item,
        show_payout: show_payout,
        payee: contractor,
        amount: expected_contractor_amount
      )

      expect(line_item.payee_type).to eq("Contractor")
      expect(line_item.payee).to eq(contractor)
      expect(line_item.payee_name).to eq(contractor.name)
    end

    it "detects contractor payment methods via polymorphic interface" do
      line_item = create(:show_payout_line_item,
        show_payout: show_payout,
        payee: contractor,
        amount: expected_contractor_amount
      )

      expect(line_item.payee_venmo_ready?).to be true
      expect(line_item.payee_has_payment_method?).to be true
    end

    it "handles contractor without payment method" do
      no_payment_contractor = create(:contractor, organization: organization)
      line_item = create(:show_payout_line_item,
        show_payout: show_payout,
        payee: no_payment_contractor,
        amount: expected_contractor_amount
      )

      expect(line_item.payee_venmo_ready?).to be false
      expect(line_item.payee_zelle_ready?).to be false
      expect(line_item.payee_has_payment_method?).to be false
    end

    it "marks the show payout as paid when contractor line item is paid" do
      line_item = create(:show_payout_line_item,
        show_payout: show_payout,
        payee: contractor,
        amount: expected_contractor_amount
      )

      user = create(:user)
      line_item.mark_as_already_paid!(user, method: "venmo")

      show_payout.reload
      expect(show_payout.paid?).to be true
    end

    it "calculates the correct amount for a 60/40 split" do
      # Create a 60/40 contract (our_share=60, contractor gets 40%)
      contract_60_40 = create(:contract, :active,
        organization: organization,
        contractor: contractor,
        contractor_name: contractor.name,
        draft_data: {
          "payment_structure" => "revenue_share",
          "payment_config" => {
            "revenue_our_share" => 60,
            "revenue_their_share" => 40,
            "revenue_settlement" => "per_event"
          }
        }
      )

      total_revenue = 1000.0
      contractor_pct = contract_60_40.contractor_share_percentage
      contractor_amount = (total_revenue * contractor_pct / 100.0).round(2)

      expect(contractor_pct).to eq(40.0)
      expect(contractor_amount).to eq(400.0)
    end

    it "returns preferred_payment_info for the contractor payee" do
      line_item = create(:show_payout_line_item,
        show_payout: show_payout,
        payee: contractor,
        amount: expected_contractor_amount
      )

      payment_info = line_item.payee_preferred_payment
      expect(payment_info).to eq({ method: "venmo", identifier: "@danvenmo" })
    end
  end
end

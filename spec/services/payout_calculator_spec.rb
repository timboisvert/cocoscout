# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutCalculator do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:show) { create(:show, production: production, date_and_time: 1.day.ago) }
  let(:role) { create(:role, production: production) }

  # Create performers
  let(:performer1) { create(:person, user: create(:user)) }
  let(:performer2) { create(:person, user: create(:user)) }

  before do
    # Assign performers to show
    create(:show_person_role_assignment, show: show, role: role, assignable: performer1)
    create(:show_person_role_assignment, show: show, role: role, assignable: performer2)
  end

  describe ".calculate" do
    context "with equal distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 100,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "calculates equal payouts for all performers" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].size).to eq(2)

        # Net revenue = 1000 - 200 = 800, split 2 ways = 400 each
        expect(result[:line_items].first[:amount]).to eq(400.0)
        expect(result[:line_items].last[:amount]).to eq(400.0)
        expect(result[:total]).to eq(800.0)
      end

      it "creates payout records" do
        result = described_class.calculate(show: show, rules: rules)

        show_payout = show.reload.show_payout
        expect(show_payout).to be_present
        expect(show_payout.line_items.count).to eq(2)
      end
    end

    context "with per_ticket distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "per_ticket",
            "per_ticket_rate" => 2.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 100,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "calculates based on ticket count" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 100 tickets * $2/ticket = $200 per performer
        expect(result[:line_items].first[:amount]).to eq(200.0)
      end
    end

    context "with per_ticket_guaranteed distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "per_ticket_guaranteed",
            "per_ticket_rate" => 2.0,
            "minimum" => 150.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 50,  # Only 50 tickets
               ticket_revenue: 500.0,
               expenses: 100.0)
        create(:show_payout, show: show)
      end

      it "uses guaranteed minimum when per_ticket is lower" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 50 tickets * $2 = $100 per person, but minimum is $150
        expect(result[:line_items].first[:amount]).to eq(150.0)
      end
    end

    context "with flat_fee distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "flat_fee",
            "flat_amount" => 75.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1000.0,
               expenses: 0.0)
        create(:show_payout, show: show)
      end

      it "pays each performer the flat amount" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].first[:amount]).to eq(75.0)
        expect(result[:line_items].last[:amount]).to eq(75.0)
        expect(result[:total]).to eq(150.0)
      end
    end

    context "with no_pay distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "no_pay"
          }
        }
      end

      before do
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0)
        create(:show_payout, show: show)
      end

      it "sets all payouts to zero" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].all? { |li| li[:amount] == 0.0 }).to be true
      end
    end

    context "with performer overrides" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          },
          "performer_overrides" => {
            performer1.id.to_s => {
              "flat_amount" => 500.0
            }
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "applies override for specific performer" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true

        performer1_item = result[:line_items].find { |li| li.payee == performer1 }
        # The override for fixed type=500 should be applied
        expect(performer1_item.amount.to_f).to eq(500.0)
      end
    end

    context "with guest performers" do
      before do
        # Add a guest assignment
        create(:show_person_role_assignment,
               show: show,
               role: role,
               guest_name: "Guest Star",
               assignable: nil)

        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1200.0,
               expenses: 0.0)
        create(:show_payout, show: show)
      end

      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          }
        }
      end

      it "includes guest in payout calculation" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 3 performers total (2 regular + 1 guest)
        expect(result[:line_items].size).to eq(3)
        guest_items = result[:line_items].select(&:is_guest?)
        regular_items = result[:line_items].reject(&:is_guest?)
        expect(guest_items.size).to eq(1)
        expect(regular_items.size).to eq(2)
        expect(guest_items.first.guest_name).to eq("Guest Star")
      end
    end

    context "error cases" do
      it "returns error when no show provided" do
        result = described_class.calculate(show: nil, rules: {})
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No show provided")
      end

      it "returns error when no rules provided" do
        result = described_class.calculate(show: show, rules: nil)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No rules provided")
      end

      it "returns error when no financials" do
        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No financial data")
      end

      it "returns error when financials incomplete" do
        create(:show_financials, show: show, data_confirmed: false, ticket_revenue: nil, flat_fee: nil)
        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No financial data")
      end

      it "returns error when no performers" do
        show.show_person_role_assignments.destroy_all
        create(:show_financials, :complete, show: show)

        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No performers assigned to this show")
      end
    end
  end

  describe ".preview" do
    it "calculates preview without persisting" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "equal" } },
        financials: { ticket_count: 100, ticket_revenue: 1000, expenses: 200, net_revenue: 800 },
        performer_count: 4
      )

      expect(result[:success]).to be true
      expect(result[:per_person]).to eq(200.0)  # 800 / 4
      expect(ShowPayout.count).to eq(0)  # Nothing persisted
    end

    it "returns preview for flat_fee method" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } },
        financials: { ticket_revenue: 1000 },
        performer_count: 3
      )

      expect(result[:success]).to be true
      expect(result[:per_person]).to eq(50.0)
      expect(result[:total]).to eq(150.0)
    end
  end
end

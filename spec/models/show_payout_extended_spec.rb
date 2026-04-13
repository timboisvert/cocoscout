# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowPayout, "extended tests", type: :model do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:show) { create(:show, production: production, date_and_time: 1.day.ago) }

  describe "status methods" do
    describe "#awaiting_payout?" do
      it "returns true when status is awaiting_payout" do
        payout = create(:show_payout, show: show, status: "awaiting_payout")
        expect(payout.awaiting_payout?).to be true
      end

      it "returns false when status is paid" do
        payout = create(:show_payout, :paid, show: show)
        expect(payout.awaiting_payout?).to be false
      end
    end

    describe "#paid?" do
      it "returns true when status is paid" do
        payout = create(:show_payout, :paid, show: show)
        expect(payout.paid?).to be true
      end
    end
  end

  describe "#awaiting_financials?" do
    it "returns true when show has no financials" do
      payout = create(:show_payout, show: show)
      expect(payout.awaiting_financials?).to be true
    end

    it "returns false when financials are complete" do
      create(:show_financials, :complete, show: show)
      payout = create(:show_payout, show: show)
      expect(payout.awaiting_financials?).to be false
    end

    it "returns true when financials exist but are incomplete" do
      create(:show_financials, show: show, data_confirmed: false, ticket_revenue: nil)
      payout = create(:show_payout, show: show)
      expect(payout.awaiting_financials?).to be true
    end
  end

  describe "#awaiting_calculation?" do
    it "returns true when financials complete but not calculated" do
      create(:show_financials, :complete, show: show)
      payout = create(:show_payout, show: show, calculated_at: nil)
      expect(payout.awaiting_calculation?).to be true
    end

    it "returns false when already calculated" do
      create(:show_financials, :complete, show: show)
      payout = create(:show_payout, show: show, calculated_at: Time.current)
      expect(payout.awaiting_calculation?).to be false
    end

    it "returns falsey when financials incomplete" do
      payout = create(:show_payout, show: show)
      expect(payout.awaiting_calculation?).to be_falsey
    end
  end

  describe "#can_edit?" do
    it "returns true when not paid" do
      payout = create(:show_payout, show: show)
      expect(payout.can_edit?).to be true
    end

    it "returns false when paid" do
      payout = create(:show_payout, :paid, show: show)
      expect(payout.can_edit?).to be false
    end
  end

  describe "#can_recalculate?" do
    it "returns true when not paid and financials complete" do
      create(:show_financials, :complete, show: show)
      payout = create(:show_payout, show: show)
      expect(payout.can_recalculate?).to be true
    end

    it "returns false when paid" do
      create(:show_financials, :complete, show: show)
      payout = create(:show_payout, :paid, show: show)
      expect(payout.can_recalculate?).to be false
    end

    it "returns falsey when financials incomplete" do
      payout = create(:show_payout, show: show)
      expect(payout.can_recalculate?).to be_falsey
    end
  end

  describe "#mark_paid!" do
    it "changes status to paid" do
      payout = create(:show_payout, show: show)
      payout.mark_paid!
      expect(payout.reload.status).to eq("paid")
    end
  end

  describe "#mark_awaiting_payout!" do
    it "changes status to awaiting_payout" do
      payout = create(:show_payout, :paid, show: show)
      payout.mark_awaiting_payout!
      expect(payout.reload.status).to eq("awaiting_payout")
    end
  end

  describe "#revert_to_awaiting_payout!" do
    it "reverts from paid to awaiting_payout" do
      payout = create(:show_payout, :paid, show: show)
      result = payout.revert_to_awaiting_payout!
      expect(payout.reload.status).to eq("awaiting_payout")
      expect(result).to be_truthy
    end

    it "returns false if not currently paid" do
      payout = create(:show_payout, show: show, status: "awaiting_payout")
      result = payout.revert_to_awaiting_payout!
      expect(result).to be false
    end
  end

  describe "#recalculate_total!" do
    it "sums line item amounts" do
      payout = create(:show_payout, show: show, total_payout: 0)
      create(:show_payout_line_item, show_payout: payout, amount: 100.0)
      create(:show_payout_line_item, show_payout: payout, amount: 75.0)

      payout.recalculate_total!
      expect(payout.reload.total_payout).to eq(175.0)
    end

    it "handles zero line items" do
      payout = create(:show_payout, show: show, total_payout: 500)
      payout.recalculate_total!
      expect(payout.reload.total_payout).to eq(0)
    end
  end

  describe "#effective_rules" do
    it "uses override rules when present" do
      payout = build(:show_payout, override_rules: { "distribution" => { "method" => "flat_fee" } })
      expect(payout.effective_rules["distribution"]["method"]).to eq("flat_fee")
    end

    it "falls back to payout_scheme rules" do
      scheme = create(:payout_scheme, rules: { "distribution" => { "method" => "per_ticket" } })
      payout = build(:show_payout, payout_scheme: scheme, override_rules: nil)
      expect(payout.effective_rules["distribution"]["method"]).to eq("per_ticket")
    end

    it "returns empty hash when no rules at all" do
      payout = build(:show_payout, payout_scheme: nil, override_rules: nil)
      expect(payout.effective_rules).to eq({})
    end
  end
end

RSpec.describe PayoutCalculator, "extended tests", type: :service do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:show) { create(:show, production: production, date_and_time: 1.day.ago) }
  let(:role) { create(:role, production: production) }
  let(:performer1) { create(:person, user: create(:user)) }
  let(:performer2) { create(:person, user: create(:user)) }
  let(:performer3) { create(:person, user: create(:user)) }

  before do
    create(:show_person_role_assignment, show: show, role: role, assignable: performer1)
    create(:show_person_role_assignment, show: show, role: role, assignable: performer2)
    create(:show_person_role_assignment, show: show, role: role, assignable: performer3)
  end

  describe "equal distribution with 3 performers" do
    before do
      create(:show_financials, :complete, show: show, ticket_revenue: 900.0, expenses: 0.0)
      create(:show_payout, show: show)
    end

    it "splits evenly 3 ways" do
      result = described_class.calculate(
        show: show,
        rules: { "distribution" => { "method" => "equal" } }
      )
      expect(result[:success]).to be true
      expect(result[:line_items].size).to eq(3)
      result[:line_items].each do |li|
        expect(li[:amount]).to eq(300.0)
      end
      expect(result[:total]).to eq(900.0)
    end
  end

  describe "equal distribution with expenses" do
    before do
      create(:show_financials, :complete, show: show, ticket_revenue: 1200.0, expenses: 300.0)
      create(:show_payout, show: show)
    end

    it "splits net revenue after expenses" do
      result = described_class.calculate(
        show: show,
        rules: { "distribution" => { "method" => "equal" } }
      )
      # Net = 1200 - 300 = 900 / 3 = 300 each
      expect(result[:total]).to eq(900.0)
      result[:line_items].each do |li|
        expect(li[:amount]).to eq(300.0)
      end
    end
  end

  describe "per_ticket with 3 performers" do
    before do
      create(:show_financials, :complete, show: show,
             ticket_count: 200, ticket_revenue: 2000.0, expenses: 0.0)
      create(:show_payout, show: show)
    end

    it "calculates per ticket amount" do
      result = described_class.calculate(
        show: show,
        rules: { "distribution" => { "method" => "per_ticket", "per_ticket_rate" => 1.50 } }
      )
      # 200 tickets * $1.50 = $300 per performer
      expect(result[:line_items].first[:amount]).to eq(300.0)
      expect(result[:total]).to eq(900.0)
    end
  end

  describe "preview calculations" do
    it "previews per_ticket distribution" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "per_ticket", "per_ticket_rate" => 2.0 } },
        financials: { ticket_count: 80, ticket_revenue: 800 },
        performer_count: 2
      )
      expect(result[:per_person]).to eq(160.0) # 80 * $2
      expect(result[:total]).to eq(320.0)
    end

    it "previews per_ticket_guaranteed with minimum triggered" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "per_ticket_guaranteed", "per_ticket_rate" => 1.0, "minimum" => 200.0 } },
        financials: { ticket_count: 50, ticket_revenue: 500 },
        performer_count: 3
      )
      # 50 * $1 = $50 < $200 minimum, so $200 each
      expect(result[:per_person]).to eq(200.0)
    end

    it "previews no_pay as zero" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "no_pay" } },
        financials: { ticket_revenue: 1000 },
        performer_count: 5
      )
      expect(result[:per_person]).to eq(0.0)
      expect(result[:total]).to eq(0.0)
    end
  end
end

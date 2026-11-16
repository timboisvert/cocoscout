# frozen_string_literal: true

require "rails_helper"

# A contract settled by the week is paid once for all its nights. Each of
# their days on Settle up counted the whole week as going out from its one
# show (Tim, 2026-11-16: Nov 13 said $736.28 to Sophomoric Songs, the week's
# three nights, and the house kept −$86.50). A day counts its own night:
# that night's sales less our fee for it, less what they owe for it.
RSpec.describe SettleUp do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:nights) { [ 12, 13, 14 ] }
  let(:now) { Time.zone.local(2026, 11, 16, 12) }

  around { |example| travel_to(now) { example.run } }

  def night_show(day) = @shows[day]

  def build_week(contract, sales:, booth_tech: true)
    @shows = nights.index_with { |day| create(:show, production: production, date_and_time: Time.zone.local(2026, 11, day, 21)) }
    if booth_tech
      @shows.each do |day, show|
        create(:contract_payment, contract: contract, direction: "incoming", amount: 50, show: show,
                                  description: "Booth Tech — Nov #{day}, 2026",
                                  settlement_method: "payout_deduction", due_date: Date.new(2026, 11, day))
      end
    end
    sales.each do |day, revenue|
      create(:show_financials, :complete, show: @shows[day], ticket_revenue: revenue, other_revenue: 0.0)
      ContractPaymentSyncService.new(@shows[day].reload).call
    end
  end

  context "with a weekly minus-fee deal" do
    let(:contract) do
      create(:contract, :active, organization: org, production: production, draft_data: {
               "payment_structure" => "flat_fee",
               "payment_config" => {
                 "flat_fee_direction" => "ticket_revenue_minus_fee",
                 "flat_fee_amount" => 250,
                 "flat_fee_basis" => "per_show",
                 "flat_fee_settlement" => "weekly"
               }
             })
    end
    let!(:week) do
      create(:contract_payment, contract: contract, direction: "outgoing",
                                description: "Ticket revenue less $750.00 fee — week of Nov 9",
                                amount: 0, amount_tbd: true, due_date: Date.new(2026, 11, 14))
    end

    before { build_week(contract, sales: { 12 => 600, 13 => 420, 14 => 616.28 }) }

    it "counts only this night of the week on its day" do
      expect(week.reload.amount.to_f).to eq(886.28)

      day = described_class.day(org, Date.new(2026, 11, 13))

      expect(day.to_people_cents).to eq(12_000) # $420 less the $250 fee, less $50 booth tech
      expect(day.kept_back_cents).to eq(5_000)
      expect(day.house_keeps_cents).to eq(day.in_cents - day.out_cents - 12_000)
    end

    it "adds up to the week across its days" do
      days = nights.map { |d| described_class.day(org, Date.new(2026, 11, d)) }

      expect(days.sum(&:to_people_cents)).to eq(73_628) # $886.28 less $150 booth tech
      expect(days.sum(&:kept_back_cents)).to eq(15_000)
    end

    it "leaves the house its fee on a night that sold under it" do
      night_show(13).show_financials.update!(ticket_revenue: 100)
      ContractPaymentSyncService.new(night_show(13).reload).call

      day = described_class.day(org, Date.new(2026, 11, 13))

      expect(day.to_people_cents).to eq(-20_000)
      expect(day.house_keeps_cents).to eq(day.in_cents - day.out_cents + 20_000)
    end
  end

  context "with a weekly revenue share" do
    let(:contract) { create(:contract, :active, :revenue_share_weekly, organization: org, production: production) }
    let!(:week) do
      create(:contract_payment, contract: contract, direction: "outgoing", description: "Revenue Share — week of Nov 9",
                                amount: 0, amount_tbd: true, due_date: Date.new(2026, 11, 14))
    end

    before { build_week(contract, sales: { 12 => 500, 13 => 300, 14 => 200 }, booth_tech: false) }

    it "counts their share of this night's sales" do
      day = described_class.day(org, Date.new(2026, 11, 13))

      expect(day.to_people_cents).to eq(12_000) # 40% of $300
      expect(day.kept_back_cents).to eq(0)
    end
  end

  # A settlement for one night is that night's, whole, as before.
  it "counts a night's own settlement as it is" do
    contract = create(:contract, :active, organization: org, production: production)
    show = create(:show, production: production, date_and_time: Time.zone.local(2026, 11, 13, 21))
    ShowFinancials.create!(show: show, revenue_type: "ticket_sales", ticket_revenue: 265, ticket_count: 13)
    contract.contract_payments.create!(description: "Nov 13 — 40% to them", amount: 106, direction: "outgoing",
                                       due_date: Date.new(2026, 11, 13), show: show)

    expect(described_class.day(org, Date.new(2026, 11, 13)).to_people_cents).to eq(10_600)
  end
end

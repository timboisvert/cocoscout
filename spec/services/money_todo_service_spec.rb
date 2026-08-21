# frozen_string_literal: true

require "rails_helper"

# The service exists so the Money hub and the pages it links to can't disagree
# about what's outstanding. These specs are mostly about that agreement.
RSpec.describe MoneyTodoService do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Todo Revue") }

  # accessible_productions reads Current.organization, which the controller sets
  # per request; a service spec has to set it itself.
  before { Current.organization = org }
  after { Current.organization = nil }

  def service(row_limit: nil)
    described_class.new(user: owner.reload, organization: org, row_limit: row_limit)
  end

  # A contract payment collected through our rail is CocoScout holding the
  # org's money until the remittance run sends it on — awaiting payout, just
  # pointed the other way, so it rides the same section.
  describe "collected contract money awaiting remittance" do
    let!(:contract) do
      create(:contract, :active, organization: org, production: production, contractor_name: "SketchFest")
    end

    def collected_payment(fee_cents: 800)
      create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                       amount: 250, due_date: 1.week.ago.to_date)
        .tap { |p| p.update!(stripe_checkout_session_id: "cs_#{p.id}", stripe_fee_cents: fee_cents) }
    end

    it "surfaces it in the payouts section, net of Stripe's fee, linking to the payment itself" do
      payment = collected_payment

      item = service.payouts.items.find { |i| i[:kind] == :remittance }
      expect(item).to be_present
      expect(item[:name]).to eq(org.name)
      expect(item[:amounts][:to_pay]).to eq(242.0)
      expect(item[:due_soon]).to eq(242.0)
      expect(item[:subtitle]).to include("collected for you from SketchFest")
      # Straight to where the money is — never a courses page.
      expect(item[:href]).to eq("/manage/money/incoming/payment/#{payment.id}")
    end

    it "counts money staged on the remittance run as in a draft run, linking to the run" do
      payment = collected_payment
      batch = PayoutBatch.create!(organization: org, status: "draft", kind: "course")
      batch_item = batch.items.create!(payee: org, amount_cents: 24_200)
      batch.payout_contributions.create!(source: payment, payout_batch_item: batch_item,
                                         payee: org, amount_cents: 24_200, label: "Remittance")

      item = service.payouts.items.find { |i| i[:kind] == :remittance }
      expect(item[:amounts][:in_draft]).to eq(242.0)
      expect(item[:amounts][:to_pay]).to be_nil
      expect(item[:href]).to eq("/manage/money/payout-runs/#{batch.id}")
    end

    it "drops out once the remittance has been paid" do
      payment = collected_payment
      batch = PayoutBatch.create!(organization: org, status: "completed", kind: "course")
      batch_item = batch.items.create!(payee: org, amount_cents: 24_200, status: "paid")
      batch.payout_contributions.create!(source: payment, payout_batch_item: batch_item,
                                         payee: org, amount_cents: 24_200, label: "Remittance")

      expect(service.payouts.items.find { |i| i[:kind] == :remittance }).to be_nil
    end

    it "ignores money recorded by hand — a check never sat in our balance" do
      create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                       amount: 250, due_date: 1.week.ago.to_date)
        .update!(payment_method: "check")

      expect(service.payouts.items.find { |i| i[:kind] == :remittance }).to be_nil
    end
  end

  # A settlement with services deducted from it hands over the NET — the hub
  # must say the same number the contract page does, not the gross.
  describe "contract payouts net of deducted services" do
    it "counts what actually moves: the share less the services netted out of it" do
      contract = create(:contract, :active, organization: org, production: production, contractor_name: "Katie Rae")
      create(:contract_payment, contract: contract, direction: "outgoing", amount: 70,
                                description: "Aug 20 — 50% to them", due_date: Date.current)
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50,
                                description: "Booth Tech", settlement_method: "payout_deduction",
                                due_date: Date.current)

      item = service.payouts.items.find { |i| i[:kind] == :contract }
      expect(item[:amount]).to eq(20.0)
      expect(item[:amounts][:to_pay]).to eq(20.0)
      expect(item[:due_soon]).to eq(20.0)
    end
  end

  describe "shows awaiting financials" do
    it "counts a started show with no financials" do
      show = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)

      expect(described_class.shows_awaiting_financials([ production ])).to contain_exactly(show)
    end

    it "leaves out shows that aren't work: future, canceled, or already confirmed" do
      create(:show, production: production, event_type: :show, date_and_time: 2.days.from_now)
      create(:show, production: production, event_type: :show, date_and_time: 2.days.ago, canceled: true)
      create(:show, production: production, event_type: :show, date_and_time: 2.days.ago).tap do |s|
        create(:show_financials, :complete, show: s, ticket_revenue: 100.0)
      end

      expect(described_class.shows_awaiting_financials([ production ])).to be_empty
    end

    # A show six hours out used to count on /all (cutoff 1.day.from_now) and not
    # on the Financials index (cutoff Time.current). One cutoff now.
    it "uses the same cutoff for the list, the per-production counts and the in-memory check" do
      soon = create(:show, production: production, event_type: :show, date_and_time: 6.hours.from_now)
      done = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)

      expect(described_class.shows_awaiting_financials([ production ])).to contain_exactly(done)
      expect(described_class.pending_financials_counts_by_production([ production ])).to eq(production.id => 1)
      expect(described_class.awaiting_financials?(soon)).to be(false)
      expect(described_class.awaiting_financials?(done)).to be(true)
    end

    it "never leaks another organization's shows" do
      other_org = create(:organization, owner: create(:user))
      other_production = create(:production, organization: other_org)
      create(:show, production: other_production, event_type: :show, date_and_time: 2.days.ago)

      expect(service.financials.count).to eq(0)
    end
  end

  describe "payouts still to pay" do
    let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
    let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 150) }
    let!(:paid_item) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 70) }
    let!(:unpaid_a) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 50) }
    let!(:unpaid_b) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 30) }

    before { paid_item.update_columns(manually_paid: true, manually_paid_at: Time.current) }

    it "totals what's still unpaid, not the show's full payout" do
      section = service.payouts

      expect(section.count).to eq(1)
      expect(section.amount).to eq(80.0)
      expect(section.amounts[:to_pay]).to eq(80.0)
      expect(section.amounts[:paid]).to eq(70.0)
    end

    it "doesn't count a production whose people are all paid" do
      [ unpaid_a, unpaid_b ].each { |li| li.update_columns(manually_paid: true, manually_paid_at: Time.current) }

      expect(service.payouts.count).to eq(0)
    end

    it "ignores a payout nobody has calculated yet" do
      payout.update_columns(calculated_at: nil)

      expect(service.payouts.count).to eq(0)
    end

    # Sorting by size put a big payment due in two months above money that went
    # overdue a fortnight ago — backwards for a list of what to chase.
    it "puts the oldest debt first, whatever it's worth" do
      later = create(:contract, organization: org, production: production, contractor_name: "Big But Later")
      later.contract_payments.create!(description: "Halloween Show", amount: 2_000, direction: "outgoing",
                                      due_date: 2.months.from_now.to_date)
      overdue = create(:contract, organization: org, contractor_name: "Small But Overdue",
                                  production: create(:production, organization: org))
      overdue.contract_payments.create!(description: "Fee", amount: 42, direction: "outgoing",
                                        due_date: 2.weeks.ago.to_date)

      names = service.payouts.items.map { |i| i[:name] }
      expect(names.index("Small But Overdue")).to be < names.index("Big But Later")
    end

    # Money in a run isn't paid until it lands. Demoting it below untouched rows
    # is how a stuck run goes unnoticed, so date is the only thing that ranks.
    it "doesn't push a row down just because its money is already moving" do
      moving = create(:contract, organization: org, contractor_name: "Already Moving",
                                 production: create(:production, organization: org))
      moving.contract_payments.create!(description: "Fee", amount: 100, direction: "outgoing",
                                       due_date: 3.months.ago.to_date, status: "paid", paid_date: Date.current)
      moving.contract_payments.create!(description: "Fee 2", amount: 50, direction: "outgoing",
                                       due_date: 3.months.ago.to_date)
      fresh = create(:contract, organization: org, contractor_name: "Just Came Up",
                                production: create(:production, organization: org))
      fresh.contract_payments.create!(description: "Fee", amount: 900, direction: "outgoing",
                                      due_date: Date.current)

      names = service.payouts.items.map { |i| i[:name] }
      expect(names.index("Already Moving")).to be < names.index("Just Came Up")
    end

    it "sorts a production by its oldest unpaid show, not by its size" do
      old_show = create(:show, production: production, event_type: :show, date_and_time: 1.year.ago)
      old_payout = ShowPayout.create!(show: old_show, status: "awaiting_payout",
                                      calculated_at: Time.current, total_payout: 5)
      ShowPayoutLineItem.create!(show_payout: old_payout, payee: create(:person), amount: 5)

      # The production row now covers a year-ago show and a three-days-ago one;
      # it sorts on the older of the two, above a fatter contract due tomorrow.
      contract = create(:contract, organization: org, production: create(:production, organization: org))
      contract.contract_payments.create!(description: "Big", amount: 9_000, direction: "outgoing",
                                         due_date: Date.tomorrow)

      expect(service.payouts.items.first[:name]).to eq(production.name)
    end

    # A show that's happened is due now; a contract payment is due when its date
    # says so. The box headlines the first kind plus the near-dated second kind,
    # and leaves a payment months out to the small-print total.
    it "splits 'to pay' into what's due this week and what's just owed" do
      contract = create(:contract, organization: org, production: create(:production, organization: org))
      contract.contract_payments.create!(description: "Soon", amount: 100, direction: "outgoing",
                                         due_date: 3.days.from_now.to_date)
      contract.contract_payments.create!(description: "Halloween", amount: 2_000, direction: "outgoing",
                                         due_date: (MoneyTodoService::DUE_SOON_HORIZON + 1.day).from_now.to_date)

      section = service.payouts

      expect(section.amounts[:to_pay]).to eq(80.0 + 100 + 2_000)
      expect(section.due_soon_amount).to eq(80.0 + 100)
    end

    it "never leaks another organization's payouts" do
      other_org = create(:organization, owner: create(:user))
      other_show = create(:show, production: create(:production, organization: other_org),
                                 event_type: :show, date_and_time: 3.days.ago)
      other_payout = ShowPayout.create!(show: other_show, status: "awaiting_payout",
                                        calculated_at: Time.current, total_payout: 999)
      ShowPayoutLineItem.create!(show_payout: other_payout, payee: create(:person), amount: 999)

      expect(service.payouts.amount).to eq(80.0)
    end
  end

  describe "money owed to us" do
    let!(:contract) { create(:contract, organization: org, production: production) }

    def incoming!(due_date:, amount: 100, settlement_method: "direct")
      ContractPayment.create!(contract: contract, direction: "incoming", status: "pending",
                              amount: amount, due_date: due_date, description: "Fee",
                              settlement_method: settlement_method)
    end

    it "takes anything overdue plus anything due inside the horizon" do
      late = incoming!(due_date: 5.days.ago.to_date)
      soon = incoming!(due_date: 12.days.from_now.to_date)
      incoming!(due_date: 60.days.from_now.to_date)

      section = service.incoming
      expect(section.items).to contain_exactly(late, soon)
      expect(section.count).to eq(2)
      expect(section.overdue_count).to eq(1)
      expect(section.overdue_amount).to eq(100.0)
    end

    # These net out of the counterparty's payout on their own — listing them as
    # work means chasing money that will never arrive as a payment.
    it "excludes charges that settle by deduction" do
      incoming!(due_date: 3.days.from_now.to_date, settlement_method: "payout_deduction")

      expect(service.incoming.count).to eq(0)
    end
  end

  # The old builder priced every production with a full FinancialSummaryService
  # pass just to decide whether it belonged in the list, then fired three more
  # queries per survivor. The absolute query count isn't worth pinning — the
  # slope is, because that's what regresses when someone reintroduces a loop.
  describe "cost" do
    # count_queries lives in spec/support/query_counting.rb.
    def production_with_work!(name)
      prod = create(:production, organization: org, name: name)
      create(:show, production: prod, event_type: :show, date_and_time: 2.days.ago)
      show = create(:show, production: prod, event_type: :show, date_and_time: 3.days.ago)
      payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 40)
      ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person), amount: 40)
      prod
    end

    it "doesn't cost more per production" do
      production_with_work!("Work 1")
      baseline = count_queries { described_class.new(user: owner.reload, organization: org).sections }

      (2..15).each { |i| production_with_work!("Work #{i}") }
      scaled = count_queries { described_class.new(user: owner.reload, organization: org).sections }

      # 14 more productions, each with work — a per-production loop would cost
      # dozens of queries here.
      expect(scaled - baseline).to be <= 3
    end
  end

  describe "row_limit" do
    before do
      6.times { |i| create(:show, production: production, event_type: :show, date_and_time: (i + 1).days.ago) }
    end

    it "truncates the rows and nothing else" do
      section = service(row_limit: 5).financials

      expect(section.items.size).to eq(5)
      expect(section.count).to eq(6)
      expect(section).to be_truncated
    end

    it "returns everything when no limit is set" do
      expect(service.financials.items.size).to eq(6)
      expect(service.financials).not_to be_truncated
    end
  end
end

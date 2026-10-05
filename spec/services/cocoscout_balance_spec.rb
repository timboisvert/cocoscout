# frozen_string_literal: true

require "rails_helper"

# Stage G: one balance for all the money CocoScout holds for a theater with
# ticketing on. Course and contract money stop riding the payout run to the
# theater's own Stripe account; they settle into the balance, fund runs and
# can be withdrawn. Theaters without ticketing keep today's remittance.
RSpec.describe CocoScoutBalance do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 10_000) }

  def payout_for(net_cents)
    offering.create_course_offering_payout!(status: "calculated", total_revenue_cents: net_cents, platform_fee_cents: 0,
                                            net_revenue_cents: net_cents, total_payout_cents: 0)
  end

  def course_sale(cents = 10_000, at: Time.current)
    registration = offering.course_registrations.create!(person: create(:person), status: :confirmed, amount_cents: cents, tax_cents: 0,
                                                         currency: "usd", registered_at: at, paid_at: at,
                                                         stripe_payment_intent_id: "pi_#{SecureRandom.hex(3)}",
                                                         cocoscout_fee_cents: (cents * 0.1).round)
    OrgCashEntry.where(source: registration).update_all(occurred_at: at)
    registration
  end

  context "with ticketing on" do
    before { TicketingProfile.for(org).update!(enabled: true) }

    it "settles course money into the available balance after two days, and lists where it came from" do
      course_sale(10_000, at: 1.hour.ago)
      summary = described_class.summary(org)
      expect(summary.settling_cents).to eq(9_000)
      expect(summary.available_cents).to eq(0)

      course_sale(10_000, at: 3.days.ago)
      summary = described_class.summary(org)
      expect(summary.settling_cents).to eq(9_000)
      expect(summary.available_cents).to eq(9_000)
      expect(summary.sources[:courses]).to eq(18_000)
      expect(summary.sources[:tickets]).to eq(0)
    end

    it "keeps the organization's course share in the balance instead of staging it on the run" do
      registration = course_sale(10_000, at: 3.days.ago)
      result = CoursePayoutRunService.add_to_run!(payout_for(9_000), added_by: owner)
      expect(result.batch.items.where(payee: org)).to be_empty
      expect(described_class.available_cents(org)).to eq(9_000)
      expect(registration).to be_confirmed
    end

    it "keeps a collected contract payment in the balance too" do
      contract = create(:contract, :active, organization: org, production: create(:production, organization: org), contractor_name: "SketchFest")
      payment = create(:contract_payment, :paid, contract: contract, direction: "incoming", amount: 250, due_date: 1.week.ago.to_date)
                  .tap { |p| p.update!(stripe_checkout_session_id: "cs_#{p.id}", stripe_fee_cents: 800) }
      OrgCashEntry.post!(organization: org, entry_type: "contract_payment", amount_cents: payment.remittable_cents, source: payment,
                         description: "Contract payment", occurred_at: 3.days.ago)
      ContractPaymentCollection.remit_to_organization!(payment)
      expect(PayoutContribution.where(source: payment)).to be_empty
      expect(described_class.available_cents(org)).to eq(payment.remittable_cents)
      expect(ContractPaymentCollection.remit_pending!(org)).to eq(0)
    end

    it "lets a payout run spend it before the bank, and a withdrawal take the rest" do
      course_sale(10_000, at: 3.days.ago)
      performer = create(:person, stripe_account_id: "acct_p", payouts_enabled: true)
      batch = PayoutBatch.open_for(org, created_by: owner)
      item = batch.items.create!(payee: performer, amount_cents: 4_000, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: performer, amount_cents: 4_000, label: "Pay")
      batch.recalculate_total!
      allow(Stripe::Transfer).to receive(:create).and_return(Stripe::Transfer.construct_from(id: "tr_1"))

      PayoutBatchService.fund!(batch)
      expect(batch.reload.balance_applied_cents).to eq(4_000)
      expect(batch.funding_payment_intent_id).to be_nil
      expect(described_class.available_cents(org)).to eq(5_000)

      withdrawal = BalanceWithdrawalService.withdraw!(org, amount_cents: 5_000, by: owner)
      expect(withdrawal.status).to eq("sent")
      expect(described_class.available_cents(org)).to eq(0)
      expect { BalanceWithdrawalService.withdraw!(org, amount_cents: 100, by: owner) }.to raise_error(BalanceWithdrawalService::Error, /Only \$0.00/)
    end

    it "keeps balance a run claimed spoken for while its bank debit is on its way, and lets it go if the debit bounces" do
      course_sale(10_000, at: 3.days.ago)
      org.update!(stripe_customer_id: "cus_sg", funding_payment_method_id: "pm_bank", funding_payment_method_type: "us_bank_account")
      PayoutFundingCredit.create!(organization: org, amount_cents: 1_000, note: "Paid another way")
      performer = create(:person, stripe_account_id: "acct_p", payouts_enabled: true)
      batch = PayoutBatch.open_for(org, created_by: owner)
      item = batch.items.create!(payee: performer, amount_cents: 20_000, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: performer, amount_cents: 20_000, label: "Pay")
      batch.recalculate_total!
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_ach", status: "processing", amount: 10_000))

      PayoutBatchService.fund!(batch)
      expect(batch.reload.attributes.slice("status", "balance_applied_cents", "credit_applied_cents"))
        .to eq("status" => "funding", "balance_applied_cents" => 9_000, "credit_applied_cents" => 1_000)
      expect(described_class.available_cents(org)).to eq(0)
      expect { BalanceWithdrawalService.withdraw!(org, amount_cents: 100, by: owner) }.to raise_error(BalanceWithdrawalService::Error, /Only \$0.00/)

      PayoutBatchService.funding_failed!(batch)
      expect(batch.reload.attributes.slice("status", "balance_applied_cents", "credit_applied_cents"))
        .to eq("status" => "failed", "balance_applied_cents" => 0, "credit_applied_cents" => 0)
      expect(PayoutFundingCredit.available_cents(org)).to eq(1_000)
      expect(described_class.available_cents(org)).to eq(8_000)
    end
  end

  context "without ticketing" do
    it "remits course money on the run as before, and the balance stays ticket money only" do
      course_sale(10_000, at: 3.days.ago)
      result = CoursePayoutRunService.add_to_run!(payout_for(9_000), added_by: owner)
      expect(result.batch.items.where(payee: org).sole.amount_cents).to eq(9_000)
      expect(described_class.available_cents(org)).to eq(0)
      expect(described_class.summary(org).sources[:courses]).to eq(9_000)
    end
  end
end

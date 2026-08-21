# frozen_string_literal: true

require "rails_helper"

# A payment collected while the org had no connected bank skipped its
# remittance — remit_pending! is the catch-up, run when the org's Connect
# account comes alive and from the payout screens.
RSpec.describe ContractPaymentCollection, ".remit_pending!" do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:production) { create(:production, organization: org) }
  let!(:contract) { create(:contract, :active, organization: org, production: production, contractor_name: "SketchFest") }

  def collected_payment
    create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                     amount: 250, due_date: 1.week.ago.to_date)
      .tap { |p| p.update!(stripe_checkout_session_id: "cs_#{p.id}", stripe_fee_cents: 800) }
  end

  it "queues every collected-but-unremitted payment on the org's remittance run" do
    payment = collected_payment
    org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

    expect(described_class.remit_pending!(org)).to eq(1)

    contribution = payment.reload.payout_contribution
    expect(contribution).to be_present
    expect(contribution.payee).to eq(org)
    expect(contribution.amount_cents).to eq(24_200)
    expect(contribution.payout_batch.kind).to eq("performer")
    # Held money — funding the run must not debit the org's bank for it.
    expect(contribution.held_funds?).to be(true)
    expect(contribution.payout_batch.held_cents).to eq(24_200)

    # Idempotent — a second sweep finds nothing.
    expect(described_class.remit_pending!(org)).to eq(0)
  end

  it "does nothing while the org still can't receive payouts" do
    payment = collected_payment

    expect(described_class.remit_pending!(org)).to eq(0)
    expect(payment.reload.payout_contribution).to be_nil
  end

  it "leaves hand-recorded money alone — a check never sat in our balance" do
    payment = create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                               amount: 250, due_date: 1.week.ago.to_date)
    payment.update!(payment_method: "check")
    org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

    expect(described_class.remit_pending!(org)).to eq(0)
    expect(payment.reload.payout_contribution).to be_nil
  end
end

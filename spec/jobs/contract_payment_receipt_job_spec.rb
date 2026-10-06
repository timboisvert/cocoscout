# frozen_string_literal: true

require "rails_helper"

# A receipt goes out on its own when a contract payment is paid (Tim,
# 2026-10-05), online or recorded by hand: once, with the invoice marked PAID
# attached. Invoices themselves never send on their own.
RSpec.describe ContractPaymentReceiptJob do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, name: "Stars & Garters") }
  let(:contract) { create(:contract, :active, organization: org, contractor_name: "Gigi Noble Wolf", contractor_email: "gigi@example.com") }
  let(:payment) do
    create(:contract_payment, contract: contract, direction: "incoming", amount: 250, amount_tbd: false,
                              due_date: Date.current, description: "Rental fee", settlement_method: "direct")
  end

  before { ActionMailer::Base.deliveries.clear }

  it "emails a receipt with the paid invoice attached when a payment is recorded by hand, once" do
    perform_enqueued_jobs do
      payment.mark_paid!(method: "check", reference: "1042")
      payment.update!(notes: "Thanks!")
    end

    mail = ActionMailer::Base.deliveries.last
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(mail.to).to eq([ "gigi@example.com" ])
    expect(mail.subject).to eq("Receipt from Stars & Garters: $250.00 paid")
    expect(mail[:from].display_names).to eq([ "Stars & Garters via CocoScout" ])
    expect(mail.html_part.body.decoded).to include("by check")
    expect(mail.attachments.reject(&:inline?).map(&:filename)).to eq([ "Invoice SG-0001.pdf" ])
    expect(payment.reload.contract_invoice.receipt_emailed_at).to be_present

    perform_enqueued_jobs { described_class.perform_now(payment.id) }
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "emails a receipt when it's paid online" do
    allow(ContractPaymentCollection).to receive(:record_stripe_fee!)
    session = instance_double(Stripe::Checkout::Session, id: "cs_test_1", payment_intent: "pi_test_1")

    perform_enqueued_jobs { ContractPaymentCollection.settle!(payment, session) }

    expect(ActionMailer::Base.deliveries.map(&:subject)).to eq([ "Receipt from Stars & Garters: $250.00 paid" ])
  end

  it "sends nothing for money netted out of a payout, or to a payer with no email" do
    perform_enqueued_jobs { payment.mark_paid_via_deduction!(reference: "Run 4") }
    contract.update_columns(contractor_email: nil)
    other = create(:contract_payment, contract: contract, direction: "incoming", amount: 75, amount_tbd: false, settlement_method: "direct")
    perform_enqueued_jobs { other.mark_paid!(method: "cash") }

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

# frozen_string_literal: true

require "rails_helper"

# The public pay link: a contractor settles what they owe without a CocoScout
# login, and the organization is remitted through the course payout rail.
RSpec.describe "Contract payment checkout", type: :request do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contractor) { create(:contractor, organization: org, name: "Gigi Noble Wolf") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production,
                               contractor: contractor, contractor_name: contractor.name,
                               production_name: "Funhouse")
  end
  let(:payment) do
    create(:contract_payment, contract: contract, direction: "incoming", status: "pending",
                              amount: 250, amount_tbd: false, due_date: Date.current,
                              description: "Rental fee")
  end

  def stripe_session(id: "cs_test_123", payment_status: "paid", intent: "pi_test_123")
    instance_double(
      Stripe::Checkout::Session,
      id: id,
      payment_status: payment_status,
      payment_intent: intent,
      metadata: { "contract_payment_id" => payment.id.to_s }
    )
  end

  describe "the payment page" do
    it "opens without a login and shows what's owed" do
      get pay_contract_path(token: payment.payment_token!)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gigi Noble Wolf")
      expect(response.body).to include("$250.00")
      expect(response.body).to include(org.name)
    end

    it "gives a plain not-found page for a bad token, leaking nothing" do
      get pay_contract_path(token: "not-a-real-token")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("couldn't find this payment")
      expect(response.body).not_to include("Gigi Noble Wolf")
    end

    it "shows a receipt rather than a pay button once it's paid" do
      token = payment.payment_token!
      payment.update!(status: "paid", paid_date: Date.current)

      get pay_contract_path(token: token)

      expect(response.body).to include("Payment received")
      expect(response.body).not_to include("Pay $250.00")
    end
  end

  describe "starting checkout" do
    it "sends them to Stripe with the payment stamped on the session and the charge" do
      captured = nil
      allow(Stripe::Checkout::Session).to receive(:create) do |args|
        captured = args
        instance_double(Stripe::Checkout::Session, url: "https://checkout.stripe.test/session")
      end

      post pay_contract_checkout_path(token: payment.payment_token!)

      expect(response).to redirect_to("https://checkout.stripe.test/session")
      expect(captured[:mode]).to eq("payment")
      expect(captured[:line_items].first[:price_data][:unit_amount]).to eq(25_000)
      expect(captured[:metadata][:contract_payment_id]).to eq(payment.id)
      # Session metadata doesn't reach the charge — the intent has to carry it too.
      expect(captured[:payment_intent_data][:metadata][:contract_payment_id]).to eq(payment.id)
    end

    it "won't start checkout for an amount that isn't settled yet" do
      payment.update!(amount_tbd: true, amount: 0)
      expect(Stripe::Checkout::Session).not_to receive(:create)

      post pay_contract_checkout_path(token: payment.payment_token!)

      expect(response).to redirect_to(pay_contract_path(token: payment.payment_token))
    end
  end

  describe "settling the payment" do
    before do
      allow(ContractPaymentCollection).to receive(:record_stripe_fee!) do |pmt, _intent|
        pmt.update!(stripe_fee_cents: 1_000)
      end
    end

    it "marks it paid and queues the org's remittance, net of Stripe's fee" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

      ContractPaymentCollection.settle!(payment, stripe_session)

      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("online")
      expect(payment.stripe_checkout_session_id).to eq("cs_test_123")

      contribution = PayoutContribution.find_by(source: payment)
      expect(contribution).to be_present
      expect(contribution.payee).to eq(org)
      # $250 collected less $10 in processing fees.
      expect(contribution.amount_cents).to eq(24_000)
      expect(contribution.payout_batch.kind).to eq("course")
    end

    it "settles once even if the webhook and the success page both arrive" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

      expect(ContractPaymentCollection.settle!(payment, stripe_session)).to be(true)
      expect(ContractPaymentCollection.settle!(payment, stripe_session)).to be(false)

      expect(PayoutContribution.where(source: payment).count).to eq(1)
    end

    it "still marks it paid when the org has no bank yet, holding the money" do
      ContractPaymentCollection.settle!(payment, stripe_session)

      expect(payment.reload).to be_status_paid
      expect(PayoutContribution.where(source: payment)).to be_empty
    end
  end

  describe "the token" do
    it "is stable once minted, so a link already sent keeps working" do
      first = payment.payment_token!
      expect(payment.payment_token!).to eq(first)
    end

    it "names exactly one payment" do
      other = create(:contract_payment, contract: contract, direction: "incoming", status: "pending",
                                        amount: 99, amount_tbd: false, due_date: Date.current)

      expect(other.payment_token!).not_to eq(payment.payment_token!)
    end
  end
end

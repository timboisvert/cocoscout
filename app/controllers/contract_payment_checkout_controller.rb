# frozen_string_literal: true

# Public, no-login payment page for money owed to an organization under a
# contract. Reached at /pay/contract/:token — the org copies that link and sends
# it however they like, and it's the same link a contractor with an account sees
# in My Contracts. The token is the only credential, so it names exactly one
# payment and nothing else about the contract is exposed.
#
# CocoScout collects the money into its own balance (like course registrations)
# and remits the organization's share through the course payout rail.
class ContractPaymentCheckoutController < ApplicationController
  allow_unauthenticated_access
  before_action :set_payment

  # Landing page: what's owed, to whom, and a button to pay it.
  def show
    render :paid if @payment.status_paid?
  end

  # Hand off to Stripe hosted checkout.
  def checkout
    return redirect_to pay_contract_path(token: @token) unless @payment.collectable_online?

    session = Stripe::Checkout::Session.create(
      mode: "payment",
      line_items: [ {
        quantity: 1,
        price_data: {
          currency: "usd",
          unit_amount: @payment.amount_cents,
          product_data: {
            name: @payment.description.presence || "Contract payment",
            description: [ "#{@organization.name} — #{@contract.production_name.presence || @contract.contractor_name}",
                           @payment.folded_services_summary ].compact.join(" · ")
          }
        }
      } ],
      success_url: pay_contract_success_url(token: @token) + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: pay_contract_url(token: @token),
      metadata: checkout_metadata,
      # Session metadata doesn't reach the charge, so stamp the intent too —
      # that's what shows up next to the money in the Stripe dashboard.
      # transfer_group segregates each org's money flows Stripe-side.
      payment_intent_data: {
        transfer_group: "org_#{@organization.id}",
        metadata: checkout_metadata
      }
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("Contract payment checkout failed for payment #{@payment.id}: #{e.message}")
    redirect_to pay_contract_path(token: @token),
                alert: "We couldn't reach our payment processor. Please try again."
  end

  # Stripe sends them back here. The webhook is the source of truth, but settle
  # inline too so the page tells the truth even if the webhook is slow.
  def success
    session_id = params[:session_id]
    if session_id.present?
      begin
        session = Stripe::Checkout::Session.retrieve(session_id)
        if session.payment_status == "paid" && session.metadata["contract_payment_id"].to_i == @payment.id
          ContractPaymentCollection.settle!(@payment, session)
        end
      rescue Stripe::StripeError => e
        # The webhook will still settle it; don't show them an error for this.
        Rails.logger.warn("Contract payment success lookup failed: #{e.message}")
      end
    end

    render :paid
  end

  private

  def checkout_metadata
    {
      contract_payment_id: @payment.id,
      contract_id: @contract.id,
      organization_id: @organization.id
    }
  end

  def set_payment
    @token = params[:token].to_s
    @payment = ContractPayment.find_by(payment_token: @token) if @token.present?
    return render :invalid, status: :not_found unless @payment

    @contract = @payment.contract
    @organization = @contract.organization
  end
end

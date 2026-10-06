# frozen_string_literal: true

# Public, no-login payment page for money owed to an organization under a
# contract. Reached at /pay/contract/:token — the org copies that link and sends
# it however they like, and it's the same link a contractor with an account sees
# in My Contracts. The token is the only credential, so it names exactly one
# payment and nothing else about the contract is exposed.
#
# The page is the invoice (ContractInvoice): numbered, downloadable as a PDF,
# and once paid, the receipt.
#
# CocoScout collects the money into its own balance (like course registrations)
# and remits the organization's share through the course payout rail.
class ContractPaymentCheckoutController < ApplicationController
  allow_unauthenticated_access
  before_action :set_payment

  # The invoice: what's owed, to whom, and a button to pay it (or PAID).
  def show
    @invoice = invoice_for(@payment)
  end

  # The invoice as a PDF, made fresh every time so it matches the payment.
  def invoice
    invoice = invoice_for(@payment)
    return redirect_to(pay_contract_path(token: @token)) unless invoice

    send_data InvoicePdf.new(invoice.document(pdf: true)).render, filename: invoice.filename,
                                                                  type: "application/pdf", disposition: "inline"
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

    @just_paid = @payment.reload.status_paid?
    @invoice = invoice_for(@payment)
    render :show
  end

  private

  def checkout_metadata
    {
      contract_payment_id: @payment.id,
      contract_id: @contract.id,
      organization_id: @organization.id
    }
  end

  # Its invoice, numbered the first time anyone opens it. A payment still
  # waiting on its amount has none yet; a cancelled one shows the one it had,
  # void.
  def invoice_for(payment)
    payment.invoiceable? ? ContractInvoice.for!(payment) : payment.contract_invoice
  end

  def set_payment
    @token = params[:token].to_s
    @payment = ContractPayment.find_by(payment_token: @token) if @token.present?
    return if @payment.nil? && redirect_to_combined_payment
    return render :invalid, status: :not_found, formats: :html unless @payment

    @contract = @payment.contract
    @organization = @contract.organization
  end

  # A link to a payment that was since combined into another opens the
  # combined one, whose invoice now covers it.
  def redirect_to_combined_payment
    return false if @token.blank?

    host = ContractInvoice.find_by(payment_token: @token)&.combined_into_payment
    return false if host&.payment_token.blank?

    redirect_to pay_contract_path(token: host.payment_token), notice: "This payment was combined with others into one invoice."
    true
  end
end

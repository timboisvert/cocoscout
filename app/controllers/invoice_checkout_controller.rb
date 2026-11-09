# frozen_string_literal: true

# Public, no-login page for an invoice an organization sent to anyone
# (/pay/invoice/:token): the invoice itself, a Pay button (card, and bank
# transfer for $500 and up), the PDF, and once paid, the receipt. The token
# is the only credential and names exactly one invoice.
class InvoiceCheckoutController < ApplicationController
  allow_unauthenticated_access
  before_action :set_invoice

  def show
    @invoice.update_columns(opened_at: Time.current) if @invoice.opened_at.nil?
    @document = @invoice.document
  end

  def pdf
    send_data InvoicePdf.new(@invoice.document(pdf: true)).render, filename: @invoice.filename, type: "application/pdf", disposition: "inline"
  end

  def checkout
    return redirect_to pay_invoice_path(token: @token) unless @invoice.collectable_online?

    methods = []
    methods << "card" if @invoice.pay_by_card
    methods << "us_bank_account" if @invoice.bank_transfer_allowed?
    session = Stripe::Checkout::Session.create(
      mode: "payment",
      payment_method_types: methods,
      line_items: [ { quantity: 1, price_data: { currency: "usd", unit_amount: @invoice.unpaid_cents,
                                                product_data: { name: "Invoice #{@invoice.display_number}", description: "#{@organization.name} · #{@invoice.invoice_lines.first&.description}".truncate(200) } } } ],
      success_url: pay_invoice_success_url(token: @token) + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: pay_invoice_url(token: @token),
      customer_email: @invoice.bill_to_email.presence,
      metadata: metadata,
      payment_intent_data: { transfer_group: "org_#{@organization.id}", metadata: metadata }
    )
    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("Invoice checkout failed for invoice #{@invoice.id}: #{e.message}")
    redirect_to pay_invoice_path(token: @token), alert: "We couldn't reach our payment provider. Please try again."
  end

  def success
    if params[:session_id].present?
      begin
        session = Stripe::Checkout::Session.retrieve(params[:session_id])
        InvoiceCollection.settle!(@invoice, session) if session.payment_status == "paid" && session.metadata["invoice_id"].to_i == @invoice.id
      rescue Stripe::StripeError => e
        Rails.logger.warn("Invoice success lookup failed: #{e.message}")
      end
    end
    @just_paid = @invoice.reload.paid?
    @document = @invoice.document
    render :show
  end

  private

  def metadata
    { invoice_id: @invoice.id, organization_id: @organization.id }
  end

  def set_invoice
    @token = params[:token].to_s
    @invoice = Invoice.standalone.find_by(payment_token: @token) if @token.present?
    raise ActiveRecord::RecordNotFound unless @invoice

    @organization = @invoice.organization
  end
end

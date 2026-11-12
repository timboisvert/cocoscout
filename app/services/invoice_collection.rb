# frozen_string_literal: true

# An invoice paid on its page (plan D2): the money lands in the
# organization's CocoScout balance exactly as a contract payment collected
# online does, less the card or bank fee; the receipt goes out by itself,
# and whoever made the invoice gets a notification (BooksNotices.invoice_paid).
class InvoiceCollection
  class << self
    def settle!(invoice, session)
      intent_id = session.respond_to?(:payment_intent) ? session.payment_intent : nil
      amount_cents = session.respond_to?(:amount_total) ? session.amount_total.to_i : invoice.unpaid_cents
      payment = nil
      invoice.with_lock do
        return false if invoice.invoice_payments.exists?(reference: session.id)
        return false unless invoice.open?

        payment = invoice.receive!(on: Date.current, amount_cents: amount_cents, via: "online", reference: session.id, memo: "Paid on the invoice page")
        invoice.update!(stripe_checkout_session_id: session.id, stripe_payment_intent_id: intent_id)
      end
      fee = stripe_fee_cents(intent_id)
      invoice.update!(stripe_fee_cents: fee) if fee
      OrgCashEntry.post!(organization: invoice.organization, entry_type: "invoice_payment", amount_cents: payment.amount_cents - fee.to_i,
                         source: payment, description: "Invoice #{invoice.display_number} paid online", occurred_at: Time.current)
      InvoiceDelivery.send_receipt!(invoice) if invoice.paid?
      BooksNotices.invoice_paid(invoice, payment)
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    private

    def stripe_fee_cents(intent_id)
      return nil if intent_id.blank?

      intent = Stripe::PaymentIntent.retrieve({ id: intent_id, expand: [ "latest_charge.balance_transaction" ] })
      intent.latest_charge&.balance_transaction&.fee
    rescue Stripe::StripeError => e
      Rails.logger.warn("Invoice #{intent_id}: couldn't read the fee: #{e.message}")
      nil
    end
  end
end
